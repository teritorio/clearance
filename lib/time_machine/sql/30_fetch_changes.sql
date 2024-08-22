DROP FUNCTION IF EXISTS fetch_changes();
CREATE OR REPLACE FUNCTION fetch_changes(
    group_id_polys jsonb
) RETURNS TABLE(
    objtype char(1),
    id bigint,
    geom geometry(Geometry, 4326),
    p jsonb
) AS $$ BEGIN
    DROP TABLE IF EXISTS _changes;
    CREATE TEMP TABLE _changes AS
    SELECT
        *
    FROM
        osm_changes_geom
    ;

    DROP TABLE IF EXISTS _changesets;
    CREATE TEMP TABLE _changesets AS
    SELECT
        _changes.objtype,
        _changes.id,
        json_agg(row_to_json(osm_changesets) ORDER BY osm_changesets.id) AS changesets
    FROM
        _changes
        LEFT JOIN osm_changesets ON
            osm_changesets.id = _changes.changeset_id
    WHERE
        osm_changesets.id IS NOT NULL
    GROUP BY
        _changes.objtype,
        _changes.id
    ;
    CREATE INDEX _changesets_idx ON _changesets (objtype, id);

    DROP TABLE IF EXISTS change_uniq;
    CREATE TEMP TABLE change_uniq AS
    SELECT DISTINCT ON (c.objtype, c.id)
        c.objtype,
        c.id,
        c.version,
        c.deleted,
        c.created,
        c.uid,
        c.username,
        c.tags,
        c.lon,
        c.lat,
        c.nodes,
        c.members,
        c.geom
    FROM
        _changes AS c
    ORDER BY
        c.objtype,
        c.id,
        c.version DESC,
        c.deleted DESC
    ;

    DROP TABLE _changes;

    RETURN QUERY
    WITH
        polygons AS (
            SELECT
                row_json->>0 AS group_id,
                ST_GeomFromGeoJSON(row_json->>1) AS geom
            FROM
                jsonb_array_elements(group_id_polys) AS t(row_json)
        ),
        base_i AS (
            SELECT
                base.objtype,
                base.id,
                base.version,
                false AS deleted,
                base.created,
                base.uid,
                base.username,
                base.tags,
                base.lon,
                base.lat,
                base.nodes,
                base.members,
                base.geom,
                NULL::json AS changesets,
                false AS is_change
            FROM
                osm_base AS base
                JOIN change_uniq ON
                    change_uniq.objtype = base.objtype AND
                    change_uniq.id = base.id
        ),
        changes_with_changesets AS (
            SELECT
                change_uniq.*,
                changesets,
                true AS is_change
            FROM
                change_uniq
                LEFT JOIN _changesets ON
                    change_uniq.objtype = _changesets.objtype AND
                    change_uniq.id = _changesets.id
        ),
        state AS (
            SELECT
                t.objtype,
                t.id,
                t.version,
                t.deleted,
                t.created,
                t.username,
                t.tags,
                t.members,
                t.geom,
                t.changesets,
                t.is_change,
                (SELECT array_agg(group_id) FROM polygons WHERE ST_Intersects(t.geom, polygons.geom)) AS group_ids
            FROM (
                SELECT * FROM base_i
                UNION ALL
                SELECT * FROM changes_with_changesets
            ) AS t
            ORDER BY
                t.objtype,
                t.id,
                t.is_change -- alows to replay histroy and keep changes after base
        )
    SELECT
        s.objtype,
        s.id,
        ST_Union(s.geom) AS geom,
        json_agg(row_to_json(s)::jsonb - 'objtype' - 'id')::jsonb AS p
    FROM
        state AS s
    GROUP BY
        s.objtype,
        s.id
    ORDER BY
        s.objtype,
        s.id
    ;
END; $$ LANGUAGE plpgsql PARALLEL SAFE;


DROP FUNCTION IF EXISTS fetch_locha_changes();
CREATE OR REPLACE FUNCTION fetch_locha_changes(
    group_id_polys jsonb,
    proj integer,
    distance float
) RETURNS TABLE(
    locha_id integer,
    objtype char(1),
    id bigint,
    p jsonb
) AS $$
WITH
rings AS (
SELECT
    objtype,
    id,
    ST_Transform(
        CASE
            WHEN ST_dimension(geom) = 2 THEN
                (SELECT ST_Union(ring.geom) FROM ST_DumpRings(geom) AS ring)
            ELSE
                geom
        END,
        proj
    ) AS geom,
    p
FROM
    fetch_changes(group_id_polys)
),
locha AS (
SELECT
    geom,
    coalesce(
        -- Equivalent to ST_ClusterWithinWin
        ST_ClusterDBSCAN(geom, distance, 0) OVER (),
        -- Negative value to avoid colision with cluster id
        -1 * row_number() OVER ()
    ) AS locha_id,
    objtype,
    id,
    objtype || '|' || id || '|' || (p[-1]->>'version') || '|' || (p[-1]->>'deleted') || '|' AS key,
    p
FROM
    rings
ORDER BY
    objtype,
    id,
    p[-1]->>'version',
    p[-1]->>'deleted'
),
locha_size AS (
SELECT
    locha_id,
    count(*) AS size
FROM
    locha
GROUP BY
    locha_id
),
locha_split AS (
SELECT
    -- Max 300 objects (think about nodes), max radius
    ST_ClusterKMeans(geom, (size / 300)::integer, distance*20) OVER (PARTITION BY locha_id) AS cluster_id,
    locha_id,
    objtype,
    id,
    key,
    p
FROM
    locha
    JOIN locha_size USING (locha_id)
),
g AS(
SELECT
    cluster_id,
    locha_id,
    (hashtext(string_agg(key, ',')))::bigint AS hash_keys
FROM
    locha_split
GROUP BY
    cluster_id,
    locha_id
)
SELECT
    hash_keys AS locha_id,
    objtype,
    id,
    p
FROM
    locha_split
    JOIN g ON
        g.cluster_id = locha_split.cluster_id AND
        g.locha_id = locha_split.locha_id
ORDER BY
    hash_keys
;
$$ LANGUAGE SQL PARALLEL SAFE;
