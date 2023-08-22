SET search_path TO :schema,public;

CREATE OR REPLACE VIEW osm_changes_geom AS

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

UNION ALL

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
    ST_MakeLine(
        coalesce(
            ST_SetSRID(ST_MakePoint(nodes_change.lon, nodes_change.lat), 4326),
            nodes.geom
        ) ORDER BY way_nodes.index, nodes_change.version DESC, nodes_change.deleted DESC
    ) AS geom
  FROM
    osm_changes
    JOIN unnest(nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON true
    JOIN osm_base AS nodes ON
      nodes.objtype = 'n' AND
      nodes.id = way_nodes.node_id
    LEFT JOIN osm_changes AS nodes_change ON
        nodes_change.objtype = 'n' AND
        nodes_change.id = way_nodes.node_id
  WHERE
    osm_changes.objtype = 'w'
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

-- TODO relations
;
