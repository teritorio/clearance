SET search_path TO :schema,public;

CREATE OR REPLACE VIEW osm_changes_geom_nodes AS
  SELECT
    objtype,
    id,
    version,
    deleted,
    changeset_id,
    created,
    uid,
    username,
    tags,
    lon,
    lat,
    nodes,
    members,
    ST_SetSRID(ST_MakePoint(lon, lat), 4326) AS geom
  FROM
    osm_changes
  WHERE
    objtype = 'n'
;

CREATE OR REPLACE VIEW osm_changes_geom_ways AS
WITH
t AS (
  SELECT DISTINCT ON (
    osm_changes.objtype,
    osm_changes.id,
    osm_changes.version,
    osm_changes.deleted,
    way_nodes.index
  )
    osm_changes.objtype,
    osm_changes.id,
    osm_changes.version,
    osm_changes.deleted,
    osm_changes.changeset_id,
    osm_changes.created,
    osm_changes.uid,
    osm_changes.username,
    osm_changes.tags,
    osm_changes.nodes,
    osm_changes.members,
    way_nodes.index,
    coalesce(nodes_change.lon, nodes.lon) AS lon,
    coalesce(nodes_change.lat, nodes.lat) AS lat,
    osm_changes.nodes[1] = osm_changes.nodes[array_length(osm_changes.nodes, 1)] AS is_closed
  FROM
    osm_changes
    LEFT JOIN unnest(nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON true
    LEFT JOIN osm_base AS nodes ON
      nodes.objtype = 'n' AND
      nodes.id = way_nodes.node_id
    LEFT JOIN osm_changes AS nodes_change ON
      nodes_change.objtype = 'n' AND
      nodes_change.id = way_nodes.node_id
  WHERE
    osm_changes.objtype = 'w'
  ORDER BY
    osm_changes.objtype,
    osm_changes.id,
    osm_changes.version,
    osm_changes.deleted,
    way_nodes.index,
    coalesce(nodes_change.version, nodes.version) DESC NULLS LAST,
    nodes_change.deleted DESC
),
with_geom AS (
  SELECT
    objtype,
    id,
    version,
    deleted,
    changeset_id,
    created,
    uid,
    username,
    tags,
    NULL::real as lon,
    NULL::real as lat,
    nodes,
    members,
    ST_SetSRID(ST_MakeLine(
      ST_MakePoint(lon, lat) ORDER BY index
    ), 4326) AS geom,
    is_closed
  FROM
    t
  WHERE
    lon IS NOT NULL AND
    lat IS NOT NULL
  GROUP BY
    objtype,
    id,
    version,
    deleted,
    changeset_id,
    created,
    uid,
    username,
    tags,
    nodes,
    members,
    is_closed
)
SELECT
  objtype,
  id,
  version,
  deleted,
  changeset_id,
  created,
  uid,
  username,
  tags,
  lon,
  lat,
  nodes,
  members,
  CASE
    -- Force initialy closed ways to be closed
    WHEN is_closed AND NOT ST_IsClosed(geom) THEN
      ST_AddPoint(geom, ST_PointN(geom, 1))
    ELSE
      geom
  END AS geom
FROM
  with_geom
;

CREATE OR REPLACE VIEW osm_changes_geom_relations AS
  SELECT
    osm_changes.objtype,
    osm_changes.id,
    osm_changes.version,
    osm_changes.deleted,
    osm_changes.changeset_id,
    osm_changes.created,
    osm_changes.uid,
    osm_changes.username,
    osm_changes.tags,
    osm_changes.lon,
    osm_changes.lat,
    osm_changes.nodes,
    osm_changes.members,
    ST_LineMerge(ST_Collect(
        coalesce(
            ways_change.geom,
            ways.geom
        )
    )) AS geom
  FROM
    osm_changes
    LEFT JOIN LATERAL jsonb_to_recordset(members) AS relations_members(ref bigint, role text, type text) ON
      type = 'w'
    LEFT JOIN osm_base AS ways ON
      ways.objtype = 'w' AND
      ways.id = relations_members.ref
    LEFT JOIN osm_changes_geom_ways AS ways_change ON
      ways_change.objtype = 'w' AND
      ways_change.id = relations_members.ref
  WHERE
    osm_changes.objtype = 'r'
  GROUP BY
    osm_changes.objtype,
    osm_changes.id,
    osm_changes.version,
    osm_changes.deleted,
    osm_changes.changeset_id,
    osm_changes.created,
    osm_changes.uid,
    osm_changes.username,
    osm_changes.tags,
    osm_changes.lon,
    osm_changes.lat,
    osm_changes.nodes,
    osm_changes.members
;

CREATE OR REPLACE VIEW osm_changes_geom AS
SELECT * FROM osm_changes_geom_nodes
UNION ALL
SELECT * FROM osm_changes_geom_ways
UNION ALL
SELECT * FROM osm_changes_geom_relations
;
