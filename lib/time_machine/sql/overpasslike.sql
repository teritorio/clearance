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
    :area_id IS NULL
    OR
    ST_Intersects(
      geom,
      (SELECT geom AS polygon FROM osm_base_areas WHERE id = :area_id)
    )
  )
;
