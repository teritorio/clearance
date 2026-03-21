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


DROP VIEW IF EXISTS base_internal CASCADE;
CREATE TEMP VIEW base_internal AS
WITH RECURSIVE dbscan AS (
  SELECT
    id AS way_id,
    nodes,
    id AS cluster_id
  FROM
    base_connection

  UNION

  SELECT
    base.id AS way_id,
    base.nodes,
    least(dbscan.cluster_id, base.id)
  FROM
    dbscan
    JOIN base ON
      base.nodes && dbscan.nodes AND
      base.id != dbscan.way_id
),
final_clusters AS (
  SELECT
    way_id,
    min(cluster_id) AS cluster_id
  FROM
    dbscan
  GROUP BY
    way_id
)
SELECT
    base.id,
    final_clusters.cluster_id
FROM
  base
  LEFT JOIN final_clusters ON
    final_clusters.way_id = base.id;
;

DROP VIEW IF EXISTS changes_internal CASCADE;
CREATE TEMP VIEW changes_internal AS
WITH RECURSIVE dbscan AS (
  SELECT
    id AS way_id,
    nodes,
    id AS cluster_id
  FROM
    changes_connection

  UNION

  SELECT
    changes.id AS way_id,
    changes.nodes,
    least(dbscan.cluster_id, changes.id)
  FROM
    dbscan
    JOIN changes ON
      changes.nodes && dbscan.nodes AND
      changes.id != dbscan.way_id
),
final_clusters AS (
  SELECT
    way_id,
    min(cluster_id) AS cluster_id
  FROM
    dbscan
  GROUP BY
    way_id
)
SELECT
    changes.id,
    final_clusters.cluster_id
FROM
  changes
  LEFT JOIN final_clusters ON
    final_clusters.way_id = changes.id;
;


CREATE TEMP VIEW internal AS
WITH inter AS (
  ((SELECT * FROM base_internal) EXCEPT (SELECT * FROM changes_internal))
  UNION ALL
  ((SELECT * FROM changes_internal) EXCEPT (SELECT * FROM base_internal))
)
SELECT DISTINCT ON (id)
  id,
  NULL::boolean AS base,
  NULL::boolean AS lost_connection,
  NULL::bigint AS node_id
FROM
  inter
ORDER BY
  id
;


CREATE TEMP VIEW validator_network AS
SELECT DISTINCT ON (id)
  *
FROM (
  SELECT * FROM lost_connection
  UNION ALL
  SELECT * FROM internal
) AS t
ORDER BY
  id,
  base
;
