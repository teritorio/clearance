SELECT
  objtype,
  id,
  version,
  created AS timestamp,
  tags,
  ST_X(
    CASE objtype
      WHEN 'n' THEN geom
      WHEN 'w' THEN ST_LineInterpolatePoint(geom, 0.5)
      WHEN 'r' THEN ST_Centroid(geom)
    END) AS lon,
  ST_Y(
    CASE objtype
      WHEN 'n' THEN geom
      WHEN 'w' THEN ST_LineInterpolatePoint(geom, 0.5)
      WHEN 'r' THEN ST_Centroid(geom)
    END) AS lat
FROM
  osm_base
WHERE
  (:osm_filter_tags) AND
  (
    :area_ids IS NULL
    OR
    ST_Intersects(
      geom,
      (SELECT ST_Union(geom) AS polygon FROM osm_base_areas WHERE id = ANY(replace(replace(:area_ids, '[', '{'), ']', '}')::int[]))
    )
  )
;
