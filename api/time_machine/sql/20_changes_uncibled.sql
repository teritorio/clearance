CREATE TEMP TABLE changes_update AS
WITH
clip AS (
    SELECT
        ST_Union(ST_GeomFromGeoJSON(geom)) AS geom
    FROM
        json_array_elements_text(:polygon::json) AS t(geom)
),
base_update AS (
    SELECT
        objtype,
        id,
        version
    FROM
        osm_base,
        clip
    WHERE
        NOT (:osm_filter_tags) OR
        (:polygon IS NOT NULL AND NOT ST_Intersects(clip.geom, osm_base.geom))
),
changes AS (
    SELECT
        *
    FROM
        osm_changes
    WHERE
        NOT (:osm_filter_tags)
)
SELECT DISTINCT ON (changes.objtype, changes.id)
    changes.*
FROM
    base_update AS base
    JOIN changes ON
        changes.objtype = base.objtype AND
        changes.id = base.id
ORDER BY
    changes.objtype,
    changes.id,
    changes.version DESC
;
