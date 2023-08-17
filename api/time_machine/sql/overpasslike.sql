WITH
polygon AS (
  SELECT geom AS polygon FROM osm_base_areas WHERE id = :area_id
),
objects AS (
  SELECT
    'n' AS objtype,
    id,
    version,
    created,
    tags,
    geom
  FROM
    osm_base_nodes
  WHERE
    (:osm_filter_tags)

  UNION ALL

  SELECT
    'w' AS objtype,
    id,
    version,
    created AS timestamp,
    tags,
    ST_LineInterpolatePoint(geom, 0.5) AS geom
  FROM
    osm_base_ways
  WHERE
    (:osm_filter_tags)

  UNION ALL

  SELECT
    'r' AS objtype,
    id,
    version,
    created AS timestamp,
    tags,
    ST_Centroid(geom) AS geom
  FROM
    osm_base_relations
    LEFT JOIN polygon ON
      ST_Intersects(polygon.polygon, osm_base_relations.geom)
  WHERE
    (:area_id IS NULL OR polygon.polygon IS NOT NULL) AND
    geom IS NOT NULL AND
    (:osm_filter_tags)
)

SELECT
  objtype,
  id,
  version,
  created AS timestamp,
  tags,
  ST_X(geom) AS lon,
  ST_Y(geom) AS lat
FROM
  objects
  LEFT JOIN polygon ON
    ST_Intersects(polygon.polygon, objects.geom)
WHERE
  (:area_id IS NULL OR polygon.polygon IS NOT NULL)
;
