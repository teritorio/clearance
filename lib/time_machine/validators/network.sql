DROP FUNCTION IF EXISTS validator_network_nodes_intersection CASCADE;
CREATE OR REPLACE FUNCTION validator_network_nodes_intersection(n1_ids BIGINT[], n2_ids BIGINT[]) RETURNS TABLE (node_id BIGINT) AS $$
  SELECT unnest(n1_ids) AS node_id
  INTERSECT
  SELECT unnest(n2_ids) AS node_id
$$ LANGUAGE SQL PARALLEL SAFE;

CREATE OR REPLACE TEMP VIEW base AS
SELECT
  *
FROM
  osm_base_w
WHERE
  id = ANY(:base_ways_ids) AND
  (:osm_filter_tags)
;

CREATE OR REPLACE TEMP VIEW changes AS
SELECT
  *
FROM
  osm_changes
WHERE
  objtype = 'w' AND
  id = ANY(:change_ways_ids) AND
  (:osm_filter_tags)
;

DROP TABLE IF EXISTS base_connection CASCADE;
CREATE TEMP TABLE base_connection AS
SELECT
  way.id,
  way.nodes,
  validator_network_nodes_intersection(way.nodes, way_other.nodes) AS node_id
FROM
  base AS way
  JOIN osm_base_w AS way_other ON
    NOT way_other.id = ANY(:base_ways_ids) AND
    way.nodes && way_other.nodes AND
    (:osm_filter_tags)
WHERE
  way.id = ANY(:base_ways_ids)
;
CREATE INDEX ON base_connection USING btree(node_id);

DROP TABLE IF EXISTS changes_connection CASCADE;
CREATE TEMP TABLE changes_connection AS
SELECT
  way.id,
  way.nodes,
  validator_network_nodes_intersection(way.nodes, way_other.nodes) AS node_id
FROM
  changes AS way
  JOIN osm_base_w AS way_other ON
    NOT way_other.id = ANY(:change_ways_ids) AND
    way.nodes && way_other.nodes AND
    (:osm_filter_tags)
;
CREATE INDEX ON changes_connection USING btree(node_id);

CREATE TEMP VIEW lost_connection AS
WITH
nodes_ids AS (
  (SELECT true AS lost_connection, node_id FROM ((SELECT DISTINCT node_id FROM base_connection) EXCEPT (SELECT DISTINCT node_id FROM changes_connection)) AS t)
  UNION ALL
  (SELECT false AS lost_connection, node_id FROM ((SELECT DISTINCT node_id FROM changes_connection) EXCEPT (SELECT DISTINCT node_id FROM base_connection)) AS t)
)
(
SELECT DISTINCT ON (base_connection.id, nodes_ids.node_id)
  base_connection.id,
  true AS base,
  nodes_ids.lost_connection,
  nodes_ids.node_id
FROM
  base_connection
  JOIN nodes_ids USING (node_id)
ORDER BY
  base_connection.id,
  nodes_ids.node_id
) UNION ALL (
SELECT DISTINCT ON (changes_connection.id, nodes_ids.node_id)
  changes_connection.id,
  false AS base,
  nodes_ids.lost_connection,
  nodes_ids.node_id
FROM
  changes_connection
  JOIN nodes_ids USING (node_id)
ORDER BY
  changes_connection.id,
  nodes_ids.node_id
)
;

CREATE TEMP VIEW validator_network AS
SELECT * FROM lost_connection
;
