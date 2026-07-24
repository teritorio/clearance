DROP TABLE IF EXISTS validator_network CASCADE;
CREATE TEMP TABLE validator_network AS
WITH
osm_base_w AS (
  SELECT
    id,
    nodes,
    tags,
    geom
  FROM
    osm_base_w AS _
  WHERE
    (:osm_filter_tags)
),
osm_changes AS (
  SELECT
    locha_id,
    id,
    deleted,
    cibled,
    nodes
  FROM
    osm_changes AS _
  WHERE
    objtype = 'w' AND
    (:osm_filter_tags)
),
base_neighbors AS (
  -- Includes osm_changes deleted
  SELECT
    way.locha_id,
    way.id,
    array_agg(DISTINCT jsonb_build_object(
      'id', nodes.id,
      'way_id', _.id,
      'x', ST_X(nodes.geom),
      'y', ST_Y(nodes.geom)
    )) AS neighbors
  FROM
    osm_changes AS way
    JOIN osm_base_w USING (id)
    JOIN osm_base_w AS _ ON
      _.geom && osm_base_w.geom AND
      _.nodes && osm_base_w.nodes AND
      _.id != osm_base_w.id
    LEFT JOIN osm_changes AS other_changes ON
      other_changes.locha_id = way.locha_id AND
      other_changes.id = _.id
    JOIN LATERAL (SELECT unnest(_.nodes) INTERSECT SELECT unnest(osm_base_w.nodes)) AS inter_nodes(id) ON true
    JOIN osm_base_n AS nodes ON
      nodes.id = inter_nodes.id
  WHERE
    other_changes.id IS NULL AND
    way.cibled
  GROUP BY
    way.locha_id,
    way.id
),
osm_last_n AS (
  SELECT
    id,
    coalesce(osm_changes.deleted, false) AS deleted,
    coalesce(osm_changes.geom, osm_base_n.geom) AS geom
  FROM
    osm_base_n
    FULL JOIN osm_changes_geom AS osm_changes USING (id)
),
osm_last_w AS (
  SELECT
    id,
    coalesce(osm_changes.nodes, osm_base_w.nodes) AS nodes,
    coalesce(osm_changes.deleted, false) AS deleted,
    coalesce(osm_changes.tags, osm_base_w.tags) AS tags
  FROM
    osm_base_w
    FULL JOIN osm_changes_geom AS osm_changes USING (id)
),
changes_neighbors AS (
  -- Do not include osm_changes deleted
  SELECT
    way.locha_id,
    way.id,
    array_agg(DISTINCT jsonb_build_object(
      'id', nodes.id,
      'way_id', _.id,
      'x', ST_X(nodes.geom),
      'y', ST_Y(nodes.geom)
    )) AS neighbors
  FROM
    osm_changes AS way
    JOIN osm_last_w AS _ ON
      _.nodes && way.nodes AND
      _.id != way.id AND
      _.deleted = false AND
      (:osm_filter_tags)
    LEFT JOIN osm_changes AS other_changes ON
      other_changes.locha_id = way.locha_id AND
      other_changes.id = _.id AND
      other_changes.deleted = false
    JOIN LATERAL (SELECT unnest(_.nodes) INTERSECT SELECT unnest(way.nodes)) AS inter_nodes(id) ON true
    JOIN osm_last_n AS nodes ON
      nodes.id = inter_nodes.id
  WHERE
    other_changes.id IS NULL AND
    way.cibled AND
    way.deleted = false
  GROUP BY
    way.locha_id,
    way.id
)
SELECT
  locha_id,
  id,
  base_neighbors.neighbors AS base_neighbors,
  changes_neighbors.neighbors AS change_neighbors
FROM
  base_neighbors
  FULL JOIN changes_neighbors USING (locha_id, id)
WHERE
  array_length(base_neighbors.neighbors, 1) IS DISTINCT FROM array_length(changes_neighbors.neighbors, 1)
  OR
  (SELECT count(*) FROM (
    SELECT unnest(base_neighbors.neighbors) AS n
    EXCEPT
    SELECT unnest(changes_neighbors.neighbors) AS n
  ) AS diff) > 0
  OR
  (SELECT count(*) FROM (
    SELECT unnest(changes_neighbors.neighbors) AS n
    EXCEPT
    SELECT unnest(base_neighbors.neighbors) AS n
  ) AS diff) > 0
;
CREATE INDEX ON validator_network (locha_id);
