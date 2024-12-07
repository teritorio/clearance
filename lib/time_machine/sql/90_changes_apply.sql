DELETE FROM
    osm_base
USING
    :changes_source AS changes
WHERE
    changes.objtype = osm_base.objtype AND
    changes.id = osm_base.id AND
    changes.deleted
;

INSERT INTO
    osm_base
SELECT DISTINCT ON (objtype, id)
    objtype, id, version, changeset_id, created, uid, username, tags, lon, lat, nodes, members
FROM
    :changes_source AS changes
WHERE
    NOT changes.deleted
ORDER BY
    objtype, id, version DESC
ON CONFLICT (id, objtype) DO
UPDATE
SET
    -- objtype = EXCLUDED.objtype,
    -- id = EXCLUDED.id,
    version = EXCLUDED.version,
    -- deleted = EXCLUDED.deleted,
    changeset_id = EXCLUDED.changeset_id,
    created = EXCLUDED.created,
    uid = EXCLUDED.uid,
    username = EXCLUDED.username,
    tags = EXCLUDED.tags,
    lon = EXCLUDED.lon,
    lat = EXCLUDED.lat,
    nodes = EXCLUDED.nodes,
    members = EXCLUDED.members
;

INSERT INTO
    osm_changes_applyed
SELECT DISTINCT ON (id, objtype, version, deleted)
    changes.objtype,
    changes.id,
    changes.version,
    changes.deleted,
    changes.changeset_id,
    changes.created,
    changes.uid,
    changes.username,
    changes.tags,
    changes.lon,
    changes.lat,
    changes.nodes,
    changes.members
FROM
    osm_changes AS changes
    JOIN :changes_source AS update ON
        update.objtype = changes.objtype AND
        update.id = changes.id
ORDER BY
    changes.objtype, changes.id, changes.version DESC, changes.deleted
-- FIXME rather than check for conflicts on each, better validate data by lochas and do not re-insert objects changed only by transitivity.
ON CONFLICT ON CONSTRAINT osm_changes_applyed_pkey
DO NOTHING
;

DELETE FROM
    osm_changes AS changes
USING
    :changes_source AS update
WHERE
    update.objtype = changes.objtype AND
    update.id = changes.id
;
