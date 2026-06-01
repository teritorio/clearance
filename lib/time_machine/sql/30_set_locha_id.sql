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

DROP TABLE IF EXISTS ring_snap CASCADE;
CREATE TEMP TABLE ring_snap AS
WITH
objects AS (
    SELECT
        cc_id,
        objtype,
        id,
        version,
        deleted,
        nodes,
        geom,
        true AS is_change
    FROM osm_changes_geom
    UNION ALL
    SELECT
        NULL::bigint AS cc_id,
        base.objtype,
        base.id,
        base.version,
        false AS deleted,
        base.nodes,
        base.geom,
        false AS is_change
    FROM
        osm_base AS base
        JOIN osm_changes AS _changes ON
            _changes.objtype = base.objtype AND
            _changes.id = base.id
),
rings AS (
    SELECT
        cc_id,
        objtype,
        id,
        version,
        deleted,
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
        max(cc_id) FILTER (WHERE is_change) AS cc_id, -- there is only one version for non change
        objtype,
        id,
        max(version) FILTER (WHERE is_change) AS version, -- there is only one version for non change
        bool_and(deleted) FILTER (WHERE is_change) AS deleted,
        array_unique(array_concat(DISTINCT nodes)) AS nodes,
        ST_Union(geom) AS geom
    FROM
        rings
    GROUP BY
        objtype,
        id
)
SELECT * FROM ring_snap
;
CREATE INDEX ring_snap_idx_cc_id ON ring_snap (cc_id);

DO $$ BEGIN
    RAISE NOTICE '30_set_locha_id - ring_snap: % (%)', (SELECT COUNT(*) FROM ring_snap), pg_size_pretty(pg_total_relation_size('ring_snap'));
END; $$ LANGUAGE plpgsql;


DROP TABLE IF EXISTS locha_renum CASCADE;
CREATE TEMP TABLE locha_renum AS
WITH
cc AS (
    SELECT
        cc_id,
        ST_Union(geom) AS geom,
        ST_SnapToGrid(ST_PointOnSurface(ST_Union(geom)), :distance * 100) AS snap_geom
    FROM
        ring_snap
    GROUP BY
        cc_id
),
locha AS (
    WITH RECURSIVE
    locha AS ((
        SELECT
            NULL::bigint AS size,
            0 AS it,
            cc_id,
            geom,
            snap_geom,
            array[coalesce(
                -- Equivalent to ST_ClusterWithinWin
                ST_ClusterDBSCAN(geom, :distance, 0) OVER (PARTITION BY snap_geom),
                -- Negative value to avoid colision with cluster id
                -1 * row_number() OVER ()
            )] AS locha_id
        FROM
            cc
    )
    UNION ALL
    (
        WITH
        locha AS (SELECT * FROM locha),
        locha_size AS (SELECT snap_geom, locha_id, count(*) AS size FROM locha GROUP BY snap_geom, locha_id)
        SELECT
            locha_size.size,
            it + 1 AS it,
            cc_id,
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
    SELECT snap_geom, locha_id, cc_id
    FROM locha JOIN locha_final_size USING (snap_geom, locha_id)
    WHERE (it > 0 AND locha_final_size.size <= 99) OR it >= 5

    UNION ALL

    SELECT snap_geom, locha_id, cc_id
    FROM locha
    WHERE snap_geom IS NULL AND it = 0
),
locha_renum AS (
    SELECT
        cc_id, objtype, id, version, deleted, nodes, geom,
        dense_rank() OVER (ORDER BY snap_geom, locha_id) AS locha_id
    FROM
        locha_split
        JOIN ring_snap USING (cc_id)
)
SELECT * FROM locha_renum
;

DROP TABLE ring_snap CASCADE;

DO $$ BEGIN
    RAISE NOTICE '30_set_locha_id - locha_renum: % (%)', (SELECT COUNT(*) FROM locha_renum), pg_size_pretty(pg_total_relation_size('locha_renum'));
END; $$ LANGUAGE plpgsql;


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
        objtype = 'n'
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
    row_number() OVER () AS main_id,
    locha_ids
FROM
    t
ORDER BY
    locha_ids
;
CREATE INDEX ON object_locha_ids (id);
CREATE INDEX ON object_locha_ids (main_id);
CREATE INDEX ON object_locha_ids USING GIN (locha_ids);

DO $$ BEGIN
    RAISE NOTICE '30_set_locha_id - object_locha_ids: % (%)', (SELECT COUNT(*) FROM object_locha_ids), pg_size_pretty(pg_total_relation_size('object_locha_ids'));
END; $$ LANGUAGE plpgsql;


-- Pre-compute the neighbor graph once: the locha_ids overlaps never change,
-- only main_id does. Replacing the GIN && join inside the loop with a plain
-- integer equi-join on this table is much cheaper per iteration.
-- Store both directions so the loop needs only one join side.
CREATE TEMP TABLE object_locha_neighbors AS
SELECT DISTINCT
    o1.id AS id1,
    o2.id AS id2
FROM
    object_locha_ids AS o1
    JOIN object_locha_ids AS o2 ON
        o2.locha_ids && o1.locha_ids AND
        o2.id != o1.id
;
CREATE INDEX ON object_locha_neighbors (id1);

DO $$ BEGIN
    RAISE NOTICE '30_set_locha_id - object_locha_neighbors: % (%)', (SELECT COUNT(*) FROM object_locha_neighbors), pg_size_pretty(pg_total_relation_size('object_locha_neighbors'));
END; $$ LANGUAGE plpgsql;


DO $$
DECLARE
    changed int := 1;
BEGIN
  WHILE changed > 0 LOOP
    -- Each row jumps to the minimum main_id of all its neighbours
    UPDATE
        object_locha_ids
    SET
        main_id = sub.new_main_id
    FROM (
        SELECT
            o1.id,
            min(o2.main_id) AS new_main_id
        FROM
            object_locha_ids AS o1
            JOIN object_locha_neighbors AS n ON
                n.id1 = o1.id
            JOIN object_locha_ids AS o2 ON
                o2.id = n.id2 AND
                o2.main_id < o1.main_id
        GROUP BY
            o1.id
    ) AS sub
    WHERE
        object_locha_ids.id = sub.id AND
        sub.new_main_id < object_locha_ids.main_id
    ;

    GET DIAGNOSTICS changed = ROW_COUNT;

    RAISE NOTICE '30_set_locha_id - comp: %', changed;

    -- Pointer jump: skip to the representative's main_id
    UPDATE
        object_locha_ids
    SET
        main_id = o2.main_id
    FROM
        object_locha_ids AS o2
    WHERE
        o2.id = object_locha_ids.main_id AND
        o2.main_id < object_locha_ids.main_id
    ;
  END LOOP;
END $$;

DROP TABLE object_locha_neighbors;


DROP TABLE IF EXISTS locha_merge_ids CASCADE;
CREATE TEMP TABLE locha_merge_ids AS
SELECT
    main_id AS id,
    array_unique(array_concat(locha_ids)) AS locha_ids
FROM
    object_locha_ids
GROUP BY
    main_id
;
CREATE INDEX ON locha_merge_ids USING GIN (locha_ids);

DROP TABLE object_locha_ids CASCADE;

DO $$ BEGIN
    RAISE NOTICE '30_set_locha_id - locha_merge_ids: % (%)', (SELECT COUNT(*) FROM locha_merge_ids), pg_size_pretty(pg_total_relation_size('locha_merge_ids'));
END; $$ LANGUAGE plpgsql;


WITH
locha_merge AS (
    SELECT
        locha_renum.objtype,
        locha_renum.id,
        locha_renum.version,
        locha_renum.deleted,
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
    locha_id = g.hash_keys
FROM
    locha_merge AS locha
    LEFT JOIN g ON
        g.locha_id = locha.locha_id
WHERE
    osm_changes.objtype = locha.objtype AND
    osm_changes.id = locha.id
;
DROP TABLE locha_renum CASCADE;
DROP TABLE locha_merge_ids CASCADE;

DO $$ BEGIN
    assert (SELECT COUNT(*) FROM osm_changes WHERE locha_id IS NULL) = 0, 'locha_id should not be null';
    RAISE NOTICE '30_set_locha_id - locha: %', (SELECT count(DISTINCT locha_id) FROM osm_changes);
    RAISE NOTICE '30_set_locha_id - largest locha size: %', (SELECT array_agg(n) FROM (SELECT count(*) FROM osm_changes GROUP BY locha_id ORDER BY count(*) DESC LIMIT 10) AS t(n));
END; $$ LANGUAGE plpgsql;
