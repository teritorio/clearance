DROP FUNCTION IF EXISTS fetch_locha_changes();
CREATE OR REPLACE FUNCTION fetch_locha_changes(
    group_id_polys jsonb
) RETURNS TABLE(
    locha_id integer,
    objtype char(1),
    id bigint,
    p jsonb
) AS $$
WITH
polygons AS (
    SELECT
        row_json->>0 AS group_id,
        ST_GeomFromGeoJSON(row_json->>1) AS geom
    FROM
        jsonb_array_elements(group_id_polys) AS t(row_json)
),
objects AS (
    SELECT *, true AS is_change FROM osm_changes_geom
    UNION ALL
    SELECT
        NULL::bigint AS cc_id,
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
        true AS cibled,
        _changes.locha_id,
        false AS is_change
    FROM
        osm_base AS base
        JOIN osm_changes AS _changes ON
            _changes.objtype = base.objtype AND
            _changes.id = base.id
),
a AS (
    SELECT
        objects.*,
        row_to_json(osm_changesets) AS changeset,
        (SELECT array_agg(group_id) FROM polygons WHERE ST_Intersects(objects.geom, polygons.geom)) AS group_ids
    FROM
        objects
        LEFT JOIN osm_changesets ON
            osm_changesets.id = objects.changeset_id
),
b AS (
    SELECT
        max(locha_id) AS locha_id,
        objtype,
        id,
        jsonb_agg(
            row_to_json(a)::jsonb - 'objtype' - 'id' - 'geom' ||
            jsonb_build_object('geojson_geometry', ST_AsGeoJSON(geom))
            ORDER BY
                objtype,
                id,
                is_change -- alows to replay histroy and keep changes after base
        ) AS p
    FROM
        a
    GROUP BY
        objtype,
        id
    ORDER BY
        objtype,
        id
)
SELECT
    locha_id,
    objtype,
    id,
    p
FROM
    b
ORDER BY
    locha_id,
    objtype,
    id
;
$$ LANGUAGE SQL PARALLEL SAFE;
