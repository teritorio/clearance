WITH
ways AS (
  SELECT * FROM osm_base WHERE objtype = 'w' AND (:osm_filter_tags)
),
relations AS (
  SELECT * FROM osm_base WHERE objtype = 'r' AND (:osm_filter_tags)
)

SELECT
  'n' AS objtype,
  id,
  version,
  created AS timestamp,
  tags,
  lat,
  lon
FROM
  osm_base
WHERE
  objtype = 'n' AND
  (:osm_filter_tags)

UNION ALL

SELECT
  'w' AS objtype,
  ways.id,
  ways.version,
  ways.created AS timestamp,
  ways.tags,
  AVG(nodes.lat) AS lat,
  AVG(nodes.lon) AS lon
FROM
  ways
  LEFT JOIN osm_base AS nodes ON
    nodes.objtype = 'n' AND
    nodes.id = ANY(ways.nodes)
GROUP BY
  ways.id,
  ways.version,
  ways.created,
  ways.tags

UNION ALL

SELECT
  'r' AS objtype,
  relations.id,
  relations.version,
  relations.created AS timestamp,
  relations.tags,
  avg(coalesce(node_members.lat)) AS lat,
  avg(coalesce(node_members.lon)) AS lon
FROM
  relations
  JOIN LATERAL (
    SELECT
      *
    FROM
      jsonb_to_recordset(members) AS m(ref bigint, role text, type text)
  ) AS relations_members ON true
  LEFT JOIN osm_base AS node_members ON
    node_members.objtype = 'n' AND
    node_members.objtype = relations_members.type AND
    node_members.id = relations_members.ref
  LEFT JOIN osm_base AS way_members ON
    way_members.objtype = 'w' AND
    way_members.objtype = relations_members.type AND
    way_members.id = relations_members.ref
  LEFT JOIN osm_base AS way_nodes ON
    way_nodes.objtype = 'n' AND
    way_nodes.id = ANY(way_members.nodes)
GROUP BY
  relations.id,
  relations.version,
  relations.created,
  relations.tags
HAVING
  avg(coalesce(node_members.lat)) IS NOT NULL AND
  avg(coalesce(node_members.lon)) IS NOT NULL
;
