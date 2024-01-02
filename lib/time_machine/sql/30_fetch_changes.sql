DROP FUNCTION IF EXISTS fetch_changes();
CREATE OR REPLACE FUNCTION fetch_changes(
    group_id_polys JSON
) RETURNS TABLE(
    objtype CHAR(1),
    id BIGINT,
    p JSON
) AS $$
WITH
    polygons AS (
        SELECT
            row_json->>0 AS group_id,
            ST_GeomFromGeoJSON(row_json->>1) AS geom
        FROM
            json_array_elements(group_id_polys) AS t(row_json)
    ),
    change_uniq AS (
        SELECT
            objtype,
            id
        FROM
            osm_changes
        GROUP BY
            objtype,
            id
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
            base.geom
        FROM
            osm_base AS base
            JOIN change_uniq ON
                change_uniq.objtype = base.objtype AND
                change_uniq.id = base.id
    ),
    changes_with_changesets AS (
        SELECT DISTINCT ON (objtype, id)
            osm_changes_geom.objtype,
            osm_changes_geom.id,
            osm_changes_geom.version,
            osm_changes_geom.deleted,
            osm_changes_geom.created,
            osm_changes_geom.uid,
            osm_changes_geom.username,
            osm_changes_geom.tags,
            osm_changes_geom.lon,
            osm_changes_geom.lat,
            osm_changes_geom.nodes,
            osm_changes_geom.members,
            osm_changes_geom.geom,
            (
                SELECT
                    json_agg(row_to_json(osm_changesets) ORDER BY osm_changesets.id)
                FROM
                    osm_changes
                    JOIN osm_changesets ON
                        osm_changesets.id = osm_changes.changeset_id
                WHERE
                    osm_changes.objtype = osm_changes_geom.objtype AND
                    osm_changes.id = osm_changes_geom.id
            ) AS changesets
        FROM
            osm_changes_geom
        ORDER BY
            objtype,
            id,
            version DESC,
            deleted DESC
    ),
    state AS (
        SELECT
            objtype,
            id,
            version,
            deleted,
            created,
            username,
            tags,
            members,
            geom,
            changesets,
            coalesce(ST_HausdorffDistance(
                ST_Transform((first_value(CASE WHEN NOT is_change THEN geom END) OVER (PARTITION BY objtype, id ORDER BY is_change, version, deleted)), 2154),
                ST_Transform(geom, 2154)
            ), 0) AS geom_distance,
            is_change,
            (SELECT array_agg(group_id) FROM polygons WHERE ST_Intersects(t.geom, polygons.geom)) AS group_ids
        FROM (
                SELECT *, NULL::json AS changesets, false AS is_change FROM base_i
                UNION ALL
                SELECT *, true AS is_change FROM changes_with_changesets
            ) AS t
        ORDER BY
            objtype,
            id,
            is_change -- alows to replay histroy and keep changes after base
    )
SELECT
    objtype,
    id,
    json_agg(row_to_json(state)::jsonb - 'objtype' - 'id')::jsonb AS p
FROM
    state
GROUP BY
    objtype,
    id
ORDER BY
    objtype,
    id
;
$$ LANGUAGE SQL PARALLEL SAFE;
