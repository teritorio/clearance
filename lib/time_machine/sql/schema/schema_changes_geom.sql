SET search_path TO :"schema", public;

DROP VIEW IF EXISTS osm_changes_geom_nodes CASCADE;
CREATE OR REPLACE VIEW osm_changes_geom_nodes AS
  SELECT
    cc_id,
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
    ST_SetSRID(ST_MakePoint(lon, lat), 4326) AS geom,
    cibled,
    locha_id
  FROM
    osm_changes
  WHERE
    objtype = 'n'
;


DROP VIEW IF EXISTS osm_changes_geom_ways CASCADE;
CREATE OR REPLACE VIEW osm_changes_geom_ways AS
WITH
with_geom AS (
  SELECT
    ways.cc_id,
    ways.objtype,
    ways.id,
    ways.version,
    ways.deleted,
    ways.changeset_id,
    ways.created,
    ways.uid,
    ways.username,
    ways.tags,
    ways.lon,
    ways.lat,
    ways.nodes,
    ways.members,
    CASE WHEN array_length(array_agg(coalesce(c_nodes.geom, b_nodes.geom) ORDER BY index) FILTER (WHERE coalesce(c_nodes.geom, b_nodes.geom) IS NOT NULL), 1) > 0 THEN
      ST_SetSRID(ST_RemoveRepeatedPoints(ST_MakeLine(array_agg(coalesce(c_nodes.geom, b_nodes.geom) ORDER BY index) FILTER (WHERE coalesce(c_nodes.geom, b_nodes.geom) IS NOT NULL))), 4326)
    END AS geom,
    ways.cibled,
    ways.nodes[1] = ways.nodes[array_length(ways.nodes, 1)] AS is_closed,
    ways.locha_id
  FROM
    osm_changes AS ways
    LEFT JOIN unnest(nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON
      ways.deleted = false
    LEFT JOIN osm_changes_geom_nodes AS c_nodes ON
      c_nodes.objtype = 'n' AND
      c_nodes.id = way_nodes.node_id
    LEFT JOIN osm_base_n AS b_nodes ON
      c_nodes.id IS NULL AND
      b_nodes.id = way_nodes.node_id
  WHERE
    ways.objtype = 'w'
  GROUP BY
    ways.objtype,
    ways.id
)
SELECT
  cc_id,
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
    WHEN ST_NPoints(geom) = 1 OR ST_Length(geom) = 0 THEN
      -- Force ways with only one node to be a point
      ST_PointN(geom, 1)
    WHEN is_closed AND NOT ST_IsClosed(geom) THEN
      -- Force initialy closed ways to be closed
      ST_AddPoint(geom, ST_PointN(geom, 1))
    ELSE
      geom
  END AS geom,
  cibled,
  locha_id
FROM
  with_geom
;

DROP VIEW IF EXISTS osm_changes_geom_relations CASCADE;
CREATE OR REPLACE VIEW osm_changes_geom_relations AS
  SELECT
    osm_changes.cc_id,
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
    )) AS geom,
    osm_changes.cibled,
    osm_changes.locha_id
  FROM
    (
      SELECT
        osm_changes.*,
        coalesce(nullif(osm_changes.members, '[]'::jsonb), relation.members) AS geom_members
      FROM
        osm_changes
        LEFT JOIN osm_base_r AS relation ON
          -- In case relation is delete and also the members, get the geometry from the base version
          osm_changes.deleted = true AND
          relation.id = osm_changes.id
    ) AS osm_changes
    LEFT JOIN LATERAL jsonb_to_recordset(geom_members) AS relations_members(ref bigint, role text, type text) ON
      type = 'w'
    LEFT JOIN osm_base_w AS ways ON
      ways.id = relations_members.ref
    LEFT JOIN osm_changes_geom_ways AS ways_change ON
      ways_change.objtype = 'w' AND
      ways_change.id = relations_members.ref
  WHERE
    osm_changes.objtype = 'r'
  GROUP BY
    osm_changes.cc_id,
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
    osm_changes.cibled,
    osm_changes.locha_id
;

DROP VIEW IF EXISTS osm_changes_geom CASCADE;
CREATE OR REPLACE VIEW osm_changes_geom AS
SELECT * FROM osm_changes_geom_nodes
UNION ALL
SELECT * FROM osm_changes_geom_ways
UNION ALL
SELECT * FROM osm_changes_geom_relations
;
