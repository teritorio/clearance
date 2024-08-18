DROP TABLE IF EXISTS tmp_changes;
CREATE TEMP TABLE tmp_changes AS
WITH
clip AS (
    SELECT
        ST_Union(ST_GeomFromGeoJSON(geom)) AS geom
    FROM
        json_array_elements_text(:polygon::json) AS t(geom)
)
SELECT
    osm_changes_geom.*
FROM
    osm_changes_geom,
    clip
WHERE
    osm_changes_geom.geom IS NULL OR
    NOT (:osm_filter_tags) OR
    (:polygon IS NOT NULL AND NOT ST_Intersects(clip.geom, osm_changes_geom.geom))
;

DROP TABLE IF EXISTS changes_update;
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
        osm_base.geom IS NULL OR
        NOT (:osm_filter_tags) OR
        (:polygon IS NOT NULL AND NOT ST_Intersects(clip.geom, osm_base.geom))
)
SELECT DISTINCT ON (changes.objtype, changes.id)
    changes.*
FROM
    base_update AS base
    JOIN tmp_changes AS changes ON
        changes.objtype = base.objtype AND
        changes.id = base.id
ORDER BY
    changes.objtype,
    changes.id,
    changes.version DESC,
    changes.deleted DESC
;

DROP TABLE tmp_changes;
