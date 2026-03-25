DROP TABLE IF EXISTS buffer CASCADE;
CREATE TEMP TABLE buffer AS
SELECT
  :map_select_index AS index,
  tags->>'level' AS level,
  :map_select_distance AS distance,
  ST_Union(ST_Buffer(
    ST_Centroid(ST_Transform(geom, :proj)),
    :map_select_distance
  )) AS buffer
FROM
  osm_changes_geom AS _
WHERE
  (
    (objtype = 'n' AND id = ANY((:change_node_ids)::bigint[])) OR
    (objtype = 'w' AND id = ANY((:change_way_ids)::bigint[]))
  ) AND
  (:osm_filter_tags)
GROUP BY
  :map_select_index,
  :map_select_distance,
  tags->>'level'
;

-- Base

DROP TABLE IF EXISTS base CASCADE;
CREATE TEMP TABLE base AS
WITH
_ AS (
  SELECT tags, geom, id, 'n' AS type FROM osm_base_n
  UNION ALL
  SELECT tags, geom, id, 'w' AS type FROM osm_base_w
)
SELECT
  _.id,
  _.type,
  ST_Centroid(ST_Transform(_.geom, :proj)) AS point,
  _.tags->>'level' AS level,
  buffer.index AS index,
  buffer.distance AS distance
FROM
  _
  JOIN buffer ON
    ST_Intersects(buffer.buffer, ST_Centroid(ST_Transform(_.geom, :proj))) AND
    buffer.index = :map_select_index AND
    buffer.level IS NOT DISTINCT FROM (tags->>'level')
WHERE
  (:osm_filter_tags)
;
CREATE INDEX ON base USING GIST (point);

DROP TABLE IF EXISTS base_duplicates CASCADE;
CREATE TEMP TABLE base_duplicates AS
SELECT
  a.index,
  a.type,
  a.id,
  count(*) AS count
FROM
  base AS a
  LEFT JOIN base AS b ON
    b.index = a.index AND
    b.level IS NOT DISTINCT FROM a.level AND
    NOT (b.type = a.type AND b.id = a.id) AND
    ST_Distance(a.point, b.point) < a.distance
GROUP BY
  a.index, a.type, a.id
;


-- Changes

DROP TABLE IF EXISTS changes CASCADE;
CREATE TEMP TABLE changes AS
SELECT
  base.*
FROM
  base
  -- Exclude changes objects from base
  LEFT JOIN osm_changes_geom ON
    osm_changes_geom.id = base.id AND
    osm_changes_geom.objtype = base.type
WHERE
  osm_changes_geom IS NULL

UNION ALL

SELECT
  id,
  objtype AS type,
  ST_Centroid(ST_Transform(geom, :proj)) AS point,
  tags->>'level' AS level,
  :map_select_index AS index,
  :map_select_distance AS distance
FROM
  osm_changes_geom AS _
  JOIN buffer ON
    ST_Intersects(buffer.buffer, ST_Centroid(ST_Transform(_.geom, :proj))) AND
    buffer.index = :map_select_index AND
    buffer.level IS NOT DISTINCT FROM (tags->>'level')
WHERE
  _.deleted = false AND
  (
    (objtype = 'n' AND id = ANY((:change_node_ids)::bigint[])) OR
    (objtype = 'w' AND id = ANY((:change_way_ids)::bigint[]))
  ) AND
  (:osm_filter_tags)
;
CREATE INDEX ON changes USING GIST (point);


DROP TABLE IF EXISTS changes_duplicates CASCADE;
CREATE TEMP TABLE changes_duplicates AS
SELECT
  a.index,
  a.type,
  a.id,
  count(*) AS count
FROM
  changes AS a
  JOIN changes AS b ON
    b.index = a.index AND
    b.level IS NOT DISTINCT FROM a.level AND
    NOT (b.type = a.type AND b.id = a.id) AND
    ST_Distance(a.point, b.point) < a.distance
GROUP BY
  a.index, a.type, a.id
;


-- Diff

DROP TABLE IF EXISTS validator_duplicate CASCADE;
CREATE TEMP VIEW validator_duplicate AS
SELECT
  changes_duplicates.index,
  changes_duplicates.type,
  changes_duplicates.id,
  array_agg(base_duplicates.type || base_duplicates.id) AS duplicates
FROM
  changes_duplicates
  LEFT JOIN base_duplicates USING (index, type, id)
WHERE
  base_duplicates.id IS NULL
  OR
  (
    (
      changes_duplicates.type = 'n' AND changes_duplicates.id = ANY((:change_node_ids)::bigint[]) OR
      changes_duplicates.type = 'w' AND changes_duplicates.id = ANY((:change_way_ids)::bigint[])
    ) AND
    changes_duplicates.count > base_duplicates.count
  )
GROUP BY
  changes_duplicates.index,
  changes_duplicates.type,
  changes_duplicates.id
;
