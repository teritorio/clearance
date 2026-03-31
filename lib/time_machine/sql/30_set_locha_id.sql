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
    WHERE
        geom IS NOT NULL
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
    SELECT
        objtype,
        id,
        version,
        deleted,
        geom,
        snap_geom,
        coalesce(
            -- Equivalent to ST_ClusterWithinWin
            ST_ClusterDBSCAN(geom, :distance, 0) OVER (PARTITION BY snap_geom),
            -- Negative value to avoid colision with cluster id
            -1 * row_number() OVER ()
        ) AS locha_id
    FROM
        ring_snap
),
locha_size AS (
    SELECT
        snap_geom,
        locha_id,
        count(*) AS size
    FROM
        locha
    GROUP BY
        snap_geom,
        locha_id
),
locha_split AS (
    SELECT
        objtype,
        id,
        version,
        deleted,
        -- Max 300 objects (think about nodes), max radius
        ST_ClusterKMeans(geom, ceil(size::float / 300)::integer, :distance * 20) OVER (PARTITION BY locha.locha_id, locha.snap_geom) AS cluster_id,
        locha_id
    FROM
        locha
        JOIN locha_size USING (snap_geom, locha_id)
    WHERE
        size > 1
    UNION ALL
    SELECT
        objtype,
        id,
        version,
        deleted,
        -- Max 300 objects (think about nodes), max radius
        (SELECT sum(size) FROM locha_size) + row_number() OVER() AS cluster_id,
        locha_id
    FROM
        locha
        JOIN locha_size USING (snap_geom, locha_id)
    WHERE
        size = 1
),
g AS(
    SELECT
        locha_id,
        cluster_id,
        (hashtext(string_agg(objtype || '|' || id || '|' || version || '|' || deleted, ',')))::integer AS hash_keys
    FROM
        locha_split
    GROUP BY
        locha_id,
        cluster_id
)
UPDATE
    osm_changes
SET
    locha_id = hash_keys
FROM
    locha_split
    JOIN g ON
        g.locha_id = locha_split.locha_id AND
        g.cluster_id = locha_split.cluster_id
WHERE
    osm_changes.objtype = locha_split.objtype AND
    osm_changes.id = locha_split.id
;
