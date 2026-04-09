DROP TABLE IF EXISTS buffer CASCADE;
CREATE TEMP TABLE buffer AS
SELECT
  locha_id,
  :map_select_index AS index,
  tags->>'level' AS level,
  :map_select_distance AS distance,
  ST_Transform(
    (ST_Dump(ST_Union(ST_Buffer(
      ST_PointOnSurface(ST_Transform(geom, :proj)),
      :map_select_distance
    )))).geom,
    4326
   ) AS buffer
FROM
  osm_changes_geom AS _
WHERE
  (:osm_filter_tags)
GROUP BY
  locha_id,
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
SELECT DISTINCT ON (_.type, _.id, index)
  _.type,
  _.id,
  buffer.index AS index,
  buffer.locha_id,
  ST_PointOnSurface(_.geom) AS point,
  ST_Transform(ST_Buffer(ST_Transform(_.geom, :proj), buffer.distance), 4326) AS within_geom,
  _.tags->>'level' AS level
FROM
  _
  JOIN buffer ON
    buffer.buffer && _.geom AND
    ST_Intersects(buffer.buffer, ST_PointOnSurface(_.geom)) AND
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
    b.locha_id = a.locha_id AND
    b.level IS NOT DISTINCT FROM a.level AND
    NOT (b.type = a.type AND b.id = a.id) AND
    ST_Intersects(a.within_geom, b.point)
GROUP BY
  a.index, a.type, a.id
;


-- Changes

DROP TABLE IF EXISTS changes CASCADE;
CREATE TEMP TABLE changes AS
SELECT
  true AS base,
  base.*
FROM
  base
  -- Exclude changes objects from base
  LEFT JOIN osm_changes_geom AS _ ON
    :map_select_index = base.index AND
    _.locha_id = base.locha_id AND
    _.id = base.id AND
    _.objtype = base.type
WHERE
  _.id IS NULL

UNION ALL

SELECT DISTINCT ON (type, id, index)
  false AS base,
  objtype AS type,
  id,
  :map_select_index AS index,
  locha_id,
  ST_PointOnSurface(geom) AS point,
  ST_Transform(ST_Buffer(ST_Transform(_.geom, :proj), :map_select_distance), 4326) AS within_geom,
  tags->>'level' AS level
FROM
  osm_changes_geom AS _
WHERE
  _.deleted = false AND
  (:osm_filter_tags)
ORDER BY
  type, id, index
;
CREATE INDEX ON changes USING GIST (point);


DROP TABLE IF EXISTS changes_duplicates CASCADE;
CREATE TEMP TABLE changes_duplicates AS
SELECT
  a.type,
  a.id,
  a.index,
  a.locha_id,
  count(*) AS count,
  array_agg(b.type || b.id ORDER BY b.type, b.id) AS duplicates
FROM
  changes AS a
  JOIN changes AS b ON
    a.locha_id = b.locha_id AND
    b.index = a.index AND
    b.level IS NOT DISTINCT FROM a.level AND
    NOT (b.type = a.type AND b.id = a.id) AND
    ST_Intersects(a.within_geom, b.point)
WHERE
  a.base = false
GROUP BY
  a.index, a.locha_id, a.type, a.id
;

-- Diff

DROP TABLE IF EXISTS validator_duplicate CASCADE;
CREATE TEMP TABLE validator_duplicate AS
SELECT
  changes_duplicates.locha_id,
  changes_duplicates.index,
  changes_duplicates.type,
  changes_duplicates.id,
  coalesce(
    nullif(array_agg(base_duplicates.type || base_duplicates.id), ARRAY[NULL]::text[]),
    changes_duplicates.duplicates
  ) AS duplicates
FROM
  changes_duplicates
  LEFT JOIN base_duplicates USING (index, type, id)
WHERE
  (
    base_duplicates.id IS NULL
    -- AND changes_duplicates.count >= 1 -- implicit
  )
  OR
  (
    changes_duplicates.count > base_duplicates.count
  )
GROUP BY
  changes_duplicates.locha_id,
  changes_duplicates.index,
  changes_duplicates.type,
  changes_duplicates.id,
  changes_duplicates.count,
  changes_duplicates.duplicates
;
CREATE INDEX ON validator_duplicate(locha_id);
