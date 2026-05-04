DROP AGGREGATE IF EXISTS array_concat(anycompatiblearray);
CREATE AGGREGATE array_concat(anycompatiblearray) (
    sfunc = array_cat,
    stype = anycompatiblearray,
    initcond = '{}'
);

DROP FUNCTION IF EXISTS array_unique(anycompatiblearray);
CREATE FUNCTION array_unique(anycompatiblearray) RETURNS anycompatiblearray AS $$
SELECT array_agg(DISTINCT x) FROM unnest($1) AS x
$$ LANGUAGE SQL PARALLEL SAFE IMMUTABLE;

DROP TABLE IF EXISTS locha_renum CASCADE;
CREATE TEMP TABLE locha_renum AS
WITH
objects AS (
    SELECT *, tags = '{}'::jsonb AS no_tags, true AS is_change FROM osm_changes_geom
    UNION ALL
    SELECT
        base.objtype,
        base.id,
        base.version,
        false AS deleted,
        base.changeset_id,
        base.created,
        base.uid,
        base.username,
        base.tags,
        base.lon,
        base.lat,
        base.nodes,
        base.members,
        base.geom,
        false AS cibled,
        NULL AS locha_id,
        base.tags = '{}'::jsonb AS no_tags,
        false AS is_change
    FROM
        osm_base AS base
        JOIN osm_changes AS _changes ON
            _changes.objtype = base.objtype AND
            _changes.id = base.id
),
rings AS (
    SELECT
        objtype,
        id,
        version,
        deleted,
        no_tags,
        is_change,
        nodes,
        ST_Transform(
            CASE
                WHEN ST_dimension(geom) = 2 THEN
                    (SELECT ST_Union(ring.geom) FROM ST_DumpRings(geom) AS ring)
                ELSE
                    geom
            END,
            :proj
        ) AS geom
    FROM
        objects
),
ring_snap AS (
    SELECT
        objtype,
        id,
        max(version) FILTER (WHERE is_change) AS version, -- there is only one version for non change
        bool_and(deleted) FILTER (WHERE is_change) AS deleted,
        bool_and(no_tags) AS no_tags,
        array_unique(array_concat(DISTINCT nodes)) AS nodes,
        ST_Union(geom) AS geom,
        ST_SnapToGrid(ST_PointOnSurface(ST_Union(geom)), :distance * 100) AS snap_geom
    FROM
        rings
    GROUP BY
        objtype,
        id
),
locha AS (
    WITH RECURSIVE
    locha AS ((
        SELECT
            NULL::bigint AS size,
            0 AS it,
            objtype,
            id,
            version,
            deleted,
            no_tags,
            nodes,
            geom,
            snap_geom,
            array[coalesce(
                -- Equivalent to ST_ClusterWithinWin
                ST_ClusterDBSCAN(geom, :distance, 0) OVER (PARTITION BY snap_geom),
                -- Negative value to avoid colision with cluster id
                -1 * row_number() OVER ()
            )] AS locha_id
        FROM
            ring_snap
    )
    UNION ALL
    (
        WITH
        locha AS (SELECT * FROM locha),
        locha_size AS (SELECT snap_geom, locha_id, count(*) AS size FROM locha GROUP BY snap_geom, locha_id)
        SELECT
            locha_size.size,
            it + 1 AS it,
            objtype,
            id,
            version,
            deleted,
            no_tags,
            nodes,
            geom,
            snap_geom,
            -- Max 99 objects (think about nodes), max radius
            locha_id || array[
                coalesce(
                    nullif(
                        ST_ClusterKMeans(geom, ceil(locha_size.size::float / 99)::integer, :distance * 20)
                            OVER (PARTITION BY locha_id),
                        -1),
                    -1 * row_number() OVER (PARTITION BY locha_id)
                )
            ] AS locha_id
        FROM
            locha
            JOIN locha_size USING (snap_geom, locha_id)
        WHERE
            it < 5 AND
            (it = 0 OR locha_size.size > 99)
    ))
    SELECT * FROM locha
),
locha_final_size AS (
    SELECT snap_geom, locha_id, count(*) AS size FROM locha GROUP BY snap_geom, locha_id
),
locha_split AS (
    SELECT snap_geom, locha_id, objtype, id, version, deleted, no_tags, nodes, geom
    FROM locha JOIN locha_final_size USING (snap_geom, locha_id)
    WHERE (it > 0 AND locha_final_size.size <= 99) OR it >= 5

    UNION ALL

    SELECT snap_geom, locha_id, objtype, id, version, deleted, no_tags, nodes, geom
    FROM locha
    WHERE snap_geom IS NULL AND it = 0
),
locha_renum AS (
    SELECT
        objtype, id, version, deleted, no_tags, nodes, geom, snap_geom,
        dense_rank() OVER (ORDER BY snap_geom, locha_id) AS locha_id
    FROM
        locha_split
)
SELECT * FROM locha_renum
;


DROP TABLE IF EXISTS object_locha_ids CASCADE;
CREATE TEMP TABLE object_locha_ids AS
WITH
ways_nodes_ids AS (
    SELECT
        locha_id,
        array_unique(array_concat(nodes)) AS nodes_ids
    FROM
        locha_renum
    WHERE
        objtype = 'w'
    GROUP BY
        locha_id
),
nodes_locha_ids AS (
    SELECT
        locha_id,
        array_agg(id) AS nodes_ids
    FROM
        locha_renum
    WHERE
        objtype = 'n' AND
        NOT no_tags
    GROUP BY
        locha_id
),
t AS (
    SELECT
        array_unique(ARRAY[ways.locha_id] || array_agg(nodes.locha_id)) AS locha_ids
    FROM
        ways_nodes_ids AS ways
        LEFT JOIN nodes_locha_ids AS nodes ON
            nodes.locha_id != ways.locha_id AND
            nodes.nodes_ids && ways.nodes_ids
    GROUP BY
        ways.locha_id

    UNION ALL

    SELECT
        ARRAY[locha_id] AS locha_ids
    FROM
        locha_renum
    WHERE
        objtype != 'w'
    GROUP BY
        locha_id
)
SELECT DISTINCT ON (locha_ids)
    row_number() OVER () AS id, -- no need to be stable, just need to be unique
    locha_ids
FROM
    t
ORDER BY
    locha_ids
;
CREATE INDEX ON object_locha_ids USING GIN (locha_ids);



DROP TABLE IF EXISTS comp;
CREATE TEMP TABLE comp AS SELECT id, id AS main_id FROM object_locha_ids;
CREATE INDEX ON comp (id);

DO $$
DECLARE changed boolean := true;
BEGIN
  WHILE changed LOOP
    -- Each node jumps to the minimum comp of all its neighbors
    UPDATE
        comp
    SET
        main_id = sub.new_main_id
    FROM (
        SELECT c.id, MIN(c2.main_id) AS new_main_id
        FROM
            comp AS c
            JOIN object_locha_ids AS o1 ON
                o1.id = c.id
            JOIN object_locha_ids AS o2 ON
                o2.locha_ids && o1.locha_ids
            JOIN comp AS c2 ON
                c2.id = o2.id
        WHERE
            c2.main_id < c.main_id
        GROUP BY
            c.id
    ) AS sub
    WHERE
        comp.id = sub.id AND
        sub.new_main_id < comp.main_id
    ;

    changed := FOUND;  -- true if UPDATE modified at least one row

    -- Pointer jump: each node skips to its comp's main_id (halves remaining depth)
    UPDATE
        comp AS c
    SET
        main_id = c2.main_id
    FROM
        comp AS c2
    WHERE
        c2.id = c.main_id AND
        c2.main_id < c.main_id
    ;
  END LOOP;
END $$;


DROP TABLE IF EXISTS locha_merge_ids CASCADE;
CREATE TEMP TABLE locha_merge_ids AS
SELECT
    comp.main_id AS id,
    array_unique(array_concat(object_locha_ids.locha_ids)) AS locha_ids
FROM
    comp
    JOIN object_locha_ids ON
        object_locha_ids.id = comp.id
GROUP BY
    comp.main_id
;
CREATE INDEX ON locha_merge_ids USING GIN (locha_ids);

WITH
locha_merge AS (
    SELECT
        locha_renum.objtype,
        locha_renum.id,
        locha_renum.version,
        locha_renum.deleted,
        locha_renum.geom,
        locha_merge_ids.id AS locha_id
    FROM
        locha_renum
        JOIN locha_merge_ids ON
            array[locha_renum.locha_id] && locha_merge_ids.locha_ids
),
g AS(
    SELECT
        locha_id,
        (hashtext(string_agg(objtype || '|' || id || '|' || version || '|' || deleted, ',' ORDER BY objtype, id)))::integer AS hash_keys
    FROM
        locha_merge
    GROUP BY
        locha_id
)
UPDATE
    osm_changes
SET
    locha_id = hash_keys
FROM
    locha_merge AS locha
    JOIN g ON
        g.locha_id = locha.locha_id
WHERE
    osm_changes.objtype = locha.objtype AND
    osm_changes.id = locha.id
;

DO $$ BEGIN
    RAISE NOTICE '30_set_locha_id - locha: %', (SELECT count(DISTINCT locha_id) FROM osm_changes);
    RAISE NOTICE '30_set_locha_id - largest locha size: %', (SELECT array_agg(n) FROM (SELECT count(*) FROM osm_changes GROUP BY locha_id ORDER BY count(*) DESC LIMIT 10) AS t(n));
END; $$ LANGUAGE plpgsql;
