DELETE FROM
    osm_base AS base
USING
    :changes_source AS changes
WHERE
    changes.objtype = base.objtype AND
    changes.id = base.id AND
    changes.deleted
;

UPDATE
    osm_base AS base
SET
    -- objtype = changes.objtype,
    -- id = changes.id,
    version = changes.version,
    -- deleted = changes.deleted,
    changeset_id = changes.changeset_id,
    created = changes.created,
    uid = changes.uid,
    username = changes.username,
    tags = changes.tags,
    lon = changes.lon,
    lat = changes.lat,
    nodes = changes.nodes,
    members = changes.members
FROM
    :changes_source AS changes
WHERE
    changes.objtype = base.objtype AND
    changes.id = base.id AND
    NOT changes.deleted
;

INSERT INTO
    osm_changes_applyed
SELECT
    changes.*
FROM
    osm_changes AS changes,
    :changes_source AS update
WHERE
    update.objtype = changes.objtype AND
    update.id = changes.id AND
    update.version >= changes.version
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
