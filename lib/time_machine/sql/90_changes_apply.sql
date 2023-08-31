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
SELECT
    objtype, id, version, changeset_id, created, uid, username, tags, lon, lat, nodes, members
FROM
    :changes_source AS changes
WHERE
    NOT changes.deleted
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
SELECT
    changes.*
FROM
    osm_changes AS changes
    JOIN :changes_source AS update ON
        update.objtype = changes.objtype AND
        update.id = changes.id AND
        update.version = changes.version AND
        update.deleted = changes.deleted
;

DELETE FROM
    osm_changes AS changes
USING
    :changes_source AS update
WHERE
    update.objtype = changes.objtype AND
    update.id = changes.id AND
    update.version >= changes.version
;
