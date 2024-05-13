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
  osm_changes
  JOIN osm_base AS ways ON
    ways.objtype = 'w' AND
    ARRAY[osm_changes.id] <@ ways.nodes
WHERE
  osm_changes.objtype = 'n'
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
  osm_changes
  JOIN osm_base AS relations ON
    relations.objtype = 'r' AND
    ARRAY[osm_changes.id] @> (osm_base_idx_nodes_members(relations.members, 'n'))
WHERE
  osm_changes.objtype = 'n'
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
  osm_changes
  JOIN osm_base AS relations ON
    relations.objtype = 'r' AND
    ARRAY[osm_changes.id] @> (osm_base_idx_nodes_members(relations.members, 'w'))
WHERE
  osm_changes.objtype = 'w'
ORDER BY
  relations.id
)
ON CONFLICT (objtype, id, version, deleted) DO NOTHING
;
