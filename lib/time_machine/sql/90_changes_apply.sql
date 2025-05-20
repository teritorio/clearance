-- DO $$ BEGIN
--     RAISE NOTICE '90_changes_apply - delete: %', (SELECT COUNT(*) FROM :changes_source WHERE deleted);
-- END; $$ LANGUAGE plpgsql;

DELETE FROM
    osm_base_r AS osm_base
USING
    :changes_source AS changes
WHERE
    changes.objtype = 'r' AND
    changes.id = osm_base.id AND
    changes.deleted
;

DELETE FROM
    osm_base_w AS osm_base
USING
    :changes_source AS changes
WHERE
    changes.objtype = 'w' AND
    changes.id = osm_base.id AND
    changes.deleted
;

DELETE FROM
    osm_base_n AS osm_base
USING
    :changes_source AS changes
WHERE
    changes.objtype = 'n' AND
    changes.id = osm_base.id AND
    changes.deleted
;

-- DO $$ BEGIN
--     RAISE NOTICE '90_changes_apply - to insert: %', (SELECT COUNT(*) FROM :changes_source WHERE NOT deleted);
-- END; $$ LANGUAGE plpgsql;


INSERT INTO
    osm_base_n
SELECT DISTINCT ON (id)
    id, version, changeset_id, created, uid, username, tags, lon, lat
FROM
    :changes_source AS changes
WHERE
    NOT changes.deleted AND
    objtype = 'n'
ORDER BY
    id, version DESC
ON CONFLICT (id) DO
UPDATE
SET
    -- id = EXCLUDED.id,
    version = EXCLUDED.version,
    -- deleted = EXCLUDED.deleted,
    changeset_id = EXCLUDED.changeset_id,
    created = EXCLUDED.created,
    uid = EXCLUDED.uid,
    username = EXCLUDED.username,
    tags = EXCLUDED.tags,
    lon = EXCLUDED.lon,
    lat = EXCLUDED.lat
;

INSERT INTO
    osm_base_w
SELECT DISTINCT ON (id)
    id, version, changeset_id, created, uid, username, tags, nodes
FROM
    :changes_source AS changes
WHERE
    NOT changes.deleted AND
    objtype = 'w'
ORDER BY
    id, version DESC
ON CONFLICT (id) DO
UPDATE
SET
    -- id = EXCLUDED.id,
    version = EXCLUDED.version,
    -- deleted = EXCLUDED.deleted,
    changeset_id = EXCLUDED.changeset_id,
    created = EXCLUDED.created,
    uid = EXCLUDED.uid,
    username = EXCLUDED.username,
    tags = EXCLUDED.tags,
    nodes = EXCLUDED.nodes
;

INSERT INTO
    osm_base_r
SELECT DISTINCT ON (id)
    id, version, changeset_id, created, uid, username, tags, members
FROM
    :changes_source AS changes
WHERE
    NOT changes.deleted AND
    objtype = 'r'
ORDER BY
    id, version DESC
ON CONFLICT (id) DO
UPDATE
SET
    -- id = EXCLUDED.id,
    version = EXCLUDED.version,
    -- deleted = EXCLUDED.deleted,
    changeset_id = EXCLUDED.changeset_id,
    created = EXCLUDED.created,
    uid = EXCLUDED.uid,
    username = EXCLUDED.username,
    tags = EXCLUDED.tags,
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
