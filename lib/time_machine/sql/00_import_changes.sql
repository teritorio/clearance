CREATE TEMP TABLE osm_changes_import (LIKE osm_changes);
ALTER TABLE osm_changes_import DROP COLUMN cibled;

COPY osm_changes_import FROM ':pgcopy';

INSERT INTO osm_changes
SELECT
    *
FROM
    osm_changes_import
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
