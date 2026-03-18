DROP FUNCTION IF EXISTS validator_network_nodes_intersection CASCADE;
CREATE OR REPLACE FUNCTION validator_network_nodes_intersection(n1_ids BIGINT[], n2_ids BIGINT[]) RETURNS TABLE (node_id BIGINT) AS $$
  SELECT unnest(n1_ids) AS node_id
  INTERSECT
  SELECT unnest(n2_ids) AS node_id
$$ LANGUAGE SQL PARALLEL SAFE;

CREATE TEMP VIEW validator_network AS
WITH
base AS (
  SELECT
    way.id,
    validator_network_nodes_intersection(way.nodes, way_other.nodes) AS node_id
  FROM
    osm_base_w AS way
    JOIN osm_base_w AS way_other ON
      NOT way_other.id = ANY(:base_ways_ids) AND
      way.nodes && way_other.nodes AND
      (:osm_filter_tags)
  WHERE
    way.id = ANY(:base_ways_ids)
),
change AS (
  SELECT
    way.id,
    validator_network_nodes_intersection(way.nodes, way_other.nodes) AS node_id
  FROM
    osm_changes AS way
    JOIN osm_base_w AS way_other ON
      NOT way_other.id = ANY(:change_ways_ids) AND
      way.nodes && way_other.nodes AND
      (:osm_filter_tags)
  WHERE
    way.objtype = 'w' AND
    way.id = ANY(:change_ways_ids)
),
nodes_ids AS (
  (SELECT true AS lost_connection, node_id FROM ((SELECT DISTINCT node_id FROM base) EXCEPT (SELECT DISTINCT node_id FROM change)) AS t)
  UNION ALL
  (SELECT false AS lost_connection, node_id FROM ((SELECT DISTINCT node_id FROM change) EXCEPT (SELECT DISTINCT node_id FROM base)) AS t)
)
(
SELECT DISTINCT ON (base.id, nodes_ids.node_id)
  base.id,
  true AS base,
  nodes_ids.lost_connection,
  nodes_ids.node_id
FROM
  base
  JOIN nodes_ids USING (node_id)
ORDER BY
  base.id,
  nodes_ids.node_id
) UNION ALL (
SELECT DISTINCT ON (change.id, nodes_ids.node_id)
  change.id,
  false AS base,
  nodes_ids.lost_connection,
  nodes_ids.node_id
FROM
  change
  JOIN nodes_ids USING (node_id)
ORDER BY
  change.id,
  nodes_ids.node_id
)
;
