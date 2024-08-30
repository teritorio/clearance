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

-- Select only changes not linked to objects of interest
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
        osm_base.geom IS NOT NULL AND
        (:osm_filter_tags) AND
        (:polygon IS NULL OR ST_Intersects(clip.geom, osm_base.geom))
)
SELECT DISTINCT ON (changes.objtype, changes.id)
    changes.*
FROM
    tmp_changes AS changes
    LEFT JOIN base_update AS base ON
        base.objtype = changes.objtype AND
        base.id = changes.id
WHERE
    base.objtype IS NULL
ORDER BY
    changes.objtype,
    changes.id,
    changes.version DESC,
    changes.deleted DESC
;

DROP TABLE tmp_changes;
