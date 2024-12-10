CREATE TEMP TABLE osm_changes_import (LIKE osm_changes);
ALTER TABLE osm_changes_import DROP COLUMN cibled;

COPY osm_changes_import(
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
    members
)
FROM ':pgcopy';

DO $$ BEGIN
    RAISE NOTICE '00_import_changes - COPY: %', (SELECT COUNT(*) FROM osm_changes_import);
END; $$ LANGUAGE plpgsql;

INSERT INTO osm_changes(
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
    members
)
SELECT DISTINCT ON (id, objtype)
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
    members
FROM
    osm_changes_import
ORDER BY
    id, objtype, version DESC, deleted DESC
ON CONFLICT (id, objtype) DO
UPDATE
SET
    version = EXCLUDED.version,
    deleted = EXCLUDED.deleted,
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

DROP TABLE osm_changes_import;
