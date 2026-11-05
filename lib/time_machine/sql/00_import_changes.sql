CREATE TEMP TABLE osm_changes_import (
    objtype CHAR(1) NOT NULL,
    id BIGINT NOT NULL,
    version INTEGER NOT NULL,
    deleted BOOLEAN NOT NULL,
    changeset_id INTEGER NOT NULL,
    created TIMESTAMP (0) WITHOUT TIME ZONE,
    uid INTEGER,
    username VARCHAR(255),
    tags JSONB,
    lon REAL,
    lat REAL,
    nodes BIGINT[],
    members JSONB,
    insert_order SERIAL
);

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
    tags,
    lon,
    lat,
    nodes,
    members
)
SELECT
    objtype,
    id,
    version,
    deleted,
    changeset_id,
    created,
    uid,
    nullif(tags, '{}'::jsonb) AS tags,
    lon,
    lat,
    nodes,
    members
FROM
    osm_changes_import
ORDER BY
    insert_order
ON CONFLICT (id, objtype) DO
UPDATE
SET
    version = EXCLUDED.version,
    deleted = EXCLUDED.deleted,
    changeset_id = EXCLUDED.changeset_id,
    created = EXCLUDED.created,
    uid = EXCLUDED.uid,
    tags = EXCLUDED.tags,
    lon = EXCLUDED.lon,
    lat = EXCLUDED.lat,
    nodes = EXCLUDED.nodes,
    members = EXCLUDED.members
;

INSERT INTO osm_users(
    id,
    display_name
)
SELECT DISTINCT ON (uid)
    uid,
    username
FROM
    osm_changes_import
    LEFT JOIN osm_users ON
        osm_users.id = osm_changes_import.uid
WHERE
    uid IS NOT NULL AND
    username IS NOT NULL AND
    (
        osm_users.id IS NULL
        OR
        -- Use the the updated_at, but do not update if, we still need to fetch the orther data
        osm_users.updated_at < osm_changes_import.created
    )
ORDER BY
    uid,
    created DESC
ON CONFLICT (id) DO
UPDATE
SET
    display_name = EXCLUDED.display_name
;

DROP TABLE osm_changes_import;
