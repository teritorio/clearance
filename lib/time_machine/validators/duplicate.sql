DROP TABLE IF EXISTS buffer CASCADE;
CREATE TEMP TABLE buffer AS
SELECT
  config.key,
  config.value,
  tags->>'level' AS level,
  ST_Union(ST_Buffer(
    ST_Centroid(ST_Transform(geom, :proj)),
    config.distance
  )) AS buffer
FROM
  osm_changes_geom AS _
  JOIN validator_duplicate_config AS config ON
    _.tags?(config.key) AND _.tags->>(config.key) = config.value
WHERE
  (
    (objtype = 'n' AND id = ANY((:change_node_ids)::bigint[])) OR
    (objtype = 'w' AND id = ANY((:change_way_ids)::bigint[]))
  ) AND
  (:osm_filter_tags)
GROUP BY
  config.key,
  config.value,
  config.distance,
  level
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
  config.key,
  config.value
FROM
  _
  JOIN validator_duplicate_config AS config ON
    _.tags?(config.key) AND _.tags->>(config.key) = config.value
  JOIN buffer ON
    ST_Intersects(buffer.buffer, ST_Centroid(ST_Transform(_.geom, :proj))) AND
    buffer.key = config.key AND
    buffer.value = config.value AND
    buffer.level IS NOT DISTINCT FROM (tags->>'level')
WHERE
  (:osm_filter_tags)
;
CREATE INDEX ON base USING GIST (point);

DROP TABLE IF EXISTS base_edges CASCADE;
CREATE TEMP TABLE base_edges AS
WITH
count AS (
  SELECT
    key,
    value,
    level,
    count(*) AS count
  FROM
    base
  GROUP BY
    key, value, level
),
delaunay_edges AS (
  SELECT
    base.key,
    base.value,
    base.level,
    distance,
    (ST_Dump(ST_DelaunayTriangles(ST_Collect(point), 0, 1))).geom AS edge
  FROM
    base
    JOIN validator_duplicate_config AS config USING (key, value)
    JOIN count ON
      count.key = base.key AND
      count.value = base.value AND
      count.level IS NOT DISTINCT FROM (base.level) AND
      count.count >= 3
  GROUP BY
    base.key,
    base.value,
    base.level,
    distance

  UNION ALL

  SELECT
    base.key,
    base.value,
    base.level,
    distance,
    ST_MakeLine(point) AS edge
  FROM
    base
    JOIN validator_duplicate_config AS config USING (key, value)
    JOIN count ON
      count.key = base.key AND
      count.value = base.value AND
      count.level IS NOT DISTINCT FROM (base.level) AND
      count.count = 2
  GROUP BY
    base.key,
    base.value,
    base.level,
    distance
),
short_edge_vertex AS (
  SELECT
    key,
    value,
    level,
    unnest(ARRAY[ST_StartPoint(edge), ST_EndPoint(edge)]) AS point
  FROM
    delaunay_edges
  WHERE
    ST_Length(edge) < distance
)
SELECT
  base.key,
  base.value,
  type,
  id
FROM
  short_edge_vertex AS vertex
  JOIN base ON
    base.key = vertex.key AND
    base.value = vertex.value AND
    base.point && vertex.point

UNION ALL

SELECT
  base.key,
  base.value,
  type,
  id
FROM
  base
  JOIN validator_duplicate_config AS config USING (key, value)
  JOIN count ON
    count.key = base.key AND
    count.value = base.value AND
    count.level IS NOT DISTINCT FROM (base.level) AND
    count.count = 1
;

DROP TABLE IF EXISTS base_duplicates CASCADE;
CREATE TEMP TABLE base_duplicates AS
SELECT
  key,
  value,
  type,
  id,
  count(*) AS count
FROM
  base_edges
GROUP BY
  key, value, type, id
;


-- Changes

DROP TABLE IF EXISTS changes CASCADE;
CREATE TEMP TABLE changes AS
SELECT
  base.*
FROM
  base
  LEFT JOIN osm_changes_geom ON
    osm_changes_geom.id = base.id AND
    osm_changes_geom.objtype = base.type AND
    osm_changes_geom.deleted = true
WHERE
  osm_changes_geom IS NULL

UNION ALL

SELECT
  id,
  objtype AS type,
  ST_Centroid(ST_Transform(geom, :proj)) AS point,
  tags->>'level' AS level,
  config.key,
  config.value
FROM
  osm_changes_geom AS _
  JOIN validator_duplicate_config AS config ON
    _.tags?(config.key) AND _.tags->>(config.key) = config.value
  JOIN buffer ON
    ST_Intersects(buffer.buffer, ST_Centroid(ST_Transform(_.geom, :proj))) AND
    buffer.key = config.key AND
    buffer.value = config.value AND
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


DROP TABLE IF EXISTS changes_edges CASCADE;
CREATE TEMP TABLE changes_edges AS
WITH
count AS (
  SELECT
    key,
    value,
    level,
    count(*) AS count
  FROM
    changes
  GROUP BY
    key, value, level
),
delaunay_edges AS (
  SELECT
    changes.key,
    changes.value,
    changes.level,
    distance,
    (ST_Dump(ST_DelaunayTriangles(ST_Collect(point), 0, 1))).geom AS edge
  FROM
    changes
    JOIN validator_duplicate_config AS config USING (key, value)
    JOIN count ON
      count.key = changes.key AND
      count.value = changes.value AND
      count.level IS NOT DISTINCT FROM (changes.level) AND
      count.count >= 3
  GROUP BY
    changes.key,
    changes.value,
    changes.level,
    distance

  UNION ALL

  SELECT
    changes.key,
    changes.value,
    changes.level,
    distance,
    ST_MakeLine(point) AS edge
  FROM
    changes
    JOIN validator_duplicate_config AS config USING (key, value)
    JOIN count ON
      count.key = changes.key AND
      count.value = changes.value AND
      count.level IS NOT DISTINCT FROM (changes.level) AND
      count.count = 2
  GROUP BY
    changes.key,
    changes.value,
    changes.level,
    distance
),
short_edge_vertex AS (
  SELECT
    key,
    value,
    level,
    unnest(ARRAY[ST_StartPoint(edge), ST_EndPoint(edge)]) AS point
  FROM
    delaunay_edges
  WHERE
    ST_Length(edge) < distance
)
SELECT
  changes.key,
  changes.value,
  type,
  id
FROM
  short_edge_vertex AS vertex
  JOIN changes ON
    changes.key = vertex.key AND
    changes.value = vertex.value AND
    changes.point && vertex.point
;


DROP TABLE IF EXISTS changes_duplicates CASCADE;
CREATE TEMP TABLE changes_duplicates AS
SELECT
  key,
  value,
  type,
  id,
  count(*) AS count
FROM
  changes_edges
GROUP BY
  key, value, type, id
;


-- Diff

DROP TABLE IF EXISTS validator_duplicate CASCADE;
CREATE TEMP VIEW validator_duplicate AS
SELECT
  changes_duplicates.key,
  changes_duplicates.value,
  changes_duplicates.type,
  changes_duplicates.id
FROM
  changes_duplicates
  LEFT JOIN base_duplicates USING (key, value, type, id)
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
;
