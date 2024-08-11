INSERT INTO osm_changes
SELECT DISTINCT ON (ways.id)
  ways.objtype,
  ways.id,
  ways.version,
  false AS deleted,
  ways.changeset_id,
  ways.created,
  ways.uid,
  ways.username,
  ways.tags,
  ways.lon,
  ways.lat,
  ways.nodes,
  ways.members
FROM
  osm_changes_geom
  JOIN osm_base AS osm_base_node ON
    osm_base_node.objtype = 'n' AND
    osm_base_node.id = osm_changes_geom.id AND
    NOT ST_Equals(osm_changes_geom.geom, osm_base_node.geom)
  JOIN osm_base AS ways ON
    ways.objtype = 'w' AND
    (osm_changes_geom.geom && ways.geom OR osm_base_node.geom && ways.geom) AND
    ARRAY[osm_changes_geom.id] <@ ways.nodes
WHERE
  osm_changes_geom.objtype = 'n'
ORDER BY
  ways.id
ON CONFLICT (objtype, id, version, deleted) DO NOTHING
;

INSERT INTO osm_changes (
SELECT DISTINCT ON (relations.id)
  relations.objtype,
  relations.id,
  relations.version,
  false AS deleted,
  relations.changeset_id,
  relations.created,
  relations.uid,
  relations.username,
  relations.tags,
  relations.lon,
  relations.lat,
  relations.nodes,
  relations.members
FROM
  osm_changes_geom
  JOIN osm_base AS osm_base_node ON
    osm_base_node.objtype = 'n' AND
    osm_base_node.id = osm_changes_geom.id AND
    NOT ST_Equals(osm_changes_geom.geom, osm_base_node.geom)
  JOIN osm_base AS relations ON
    relations.objtype = 'r' AND
    (osm_changes_geom.geom && relations.geom OR osm_base_node.geom && relations.geom) AND
    ARRAY[osm_changes_geom.id] @> (osm_base_idx_nodes_members(relations.members, 'n'))
WHERE
  osm_changes_geom.objtype = 'n'
ORDER BY
  relations.id

) UNION ALL (

SELECT DISTINCT ON (relations.id)
  relations.objtype,
  relations.id,
  relations.version,
  false AS deleted,
  relations.changeset_id,
  relations.created,
  relations.uid,
  relations.username,
  relations.tags,
  relations.lon,
  relations.lat,
  relations.nodes,
  relations.members
FROM
  osm_changes_geom
  JOIN osm_base AS osm_base_way ON
    osm_base_way.objtype = 'w' AND
    osm_base_way.id = osm_changes_geom.id AND
    NOT ST_Equals(osm_changes_geom.geom, osm_base_way.geom)
  JOIN osm_base AS relations ON
    relations.objtype = 'r' AND
    (osm_changes_geom.geom && relations.geom OR osm_base_way.geom && relations.geom) AND
    ARRAY[osm_changes_geom.id] @> (osm_base_idx_nodes_members(relations.members, 'w'))
WHERE
  osm_changes_geom.objtype = 'w'
ORDER BY
  relations.id
)
ON CONFLICT (objtype, id, version, deleted) DO NOTHING
;
