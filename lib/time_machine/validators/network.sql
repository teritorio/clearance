DROP TABLE IF EXISTS validator_network CASCADE;
CREATE TEMP TABLE validator_network AS
WITH
osm_base_w AS (
  SELECT
    id,
    nodes
  FROM
    osm_base_w AS _
  WHERE
    (:osm_filter_tags)
),
osm_changes AS (
  SELECT
    *
  FROM
    osm_changes AS _
  WHERE
    objtype = 'w' AND
    (:osm_filter_tags)
),
base_neighbors AS (
  SELECT
    way.locha_id,
    way.id,
    array_agg(_.id) AS neighbors_ways
  FROM
    osm_changes AS way
    JOIN osm_base_w ON
      osm_base_w.id = way.id
    JOIN osm_base_w AS _ ON
      _.nodes && osm_base_w.nodes AND
      _.id != osm_base_w.id
  GROUP BY
    way.locha_id,
    way.id
),
osm_last AS (
  SELECT
    osm_base_w.id,
    coalesce(osm_changes.nodes, osm_base_w.nodes) AS nodes,
    coalesce(osm_changes.deleted, false) AS deleted
  FROM
    osm_base_w
    LEFT JOIN osm_changes ON
      osm_changes.objtype = 'w' AND
      osm_changes.id = osm_base_w.id
),
changes_neighbors AS (
  SELECT
    way.locha_id,
    way.id,
    array_agg(c.id) AS neighbors_ways
  FROM
    osm_changes AS way
    JOIN osm_last AS c ON
      c.nodes && way.nodes AND
      c.id != way.id AND
      c.deleted = false
  WHERE
    way.deleted = false
  GROUP BY
    way.locha_id,
    way.id
)
SELECT
  locha_id,
  id,
  base_neighbors.neighbors_ways AS base_neighbors_ways,
  changes_neighbors.neighbors_ways AS change_neighbors_ways
FROM
  base_neighbors
  FULL JOIN changes_neighbors USING (locha_id, id)
WHERE
  base_neighbors.neighbors_ways IS DISTINCT FROM changes_neighbors.neighbors_ways
;
CREATE INDEX ON validator_network (locha_id);
