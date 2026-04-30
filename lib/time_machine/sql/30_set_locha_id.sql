WITH
objects AS (
    SELECT *, true AS is_change FROM osm_changes_geom
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
        is_change,
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
        max(version) FILTER (WHERE is_change) AS version,-- there is only one version for non change
        bool_and(deleted) FILTER (WHERE is_change) AS deleted,
        ST_Union(geom) AS geom,
        ST_SnapToGrid(ST_Centroid(ST_Union(geom)), :distance * 100) AS snap_geom
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
            geom,
            snap_geom,
            -- Max 200 objects (think about nodes), max radius
            locha_id || array[
                coalesce(
                    nullif(
                        ST_ClusterKMeans(geom, ceil(locha_size.size::float / 200)::integer, :distance * 20)
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
            (it = 0 OR locha_size.size > 200)
    ))
    SELECT * FROM locha
),
locha_final_size AS (
    SELECT snap_geom, locha_id, count(*) AS size FROM locha GROUP BY snap_geom, locha_id
),
locha_split AS (
    SELECT snap_geom, locha_id, objtype, id, version, deleted, geom
    FROM locha JOIN locha_final_size USING (snap_geom, locha_id)
    WHERE (it > 0 AND locha_final_size.size <= 200) OR it >= 5
),
g AS(
    SELECT
        snap_geom,
        locha_id,
        (hashtext(string_agg(objtype || '|' || id || '|' || version || '|' || deleted, ',')))::integer AS hash_keys
    FROM
        locha_split
    GROUP BY
        snap_geom,
        locha_id
)
UPDATE
    osm_changes
SET
    locha_id = hash_keys
FROM
    locha_split
    JOIN g ON
        g.snap_geom = locha_split.snap_geom AND
        g.locha_id = locha_split.locha_id
WHERE
    osm_changes.objtype = locha_split.objtype AND
    osm_changes.id = locha_split.id
;
