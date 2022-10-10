BEGIN;

WITH changes_without_base AS (
    SELECT
        changes.objtype,
        changes.id
    FROM
        osm_changes AS changes
        LEFT JOIN osm_base AS base ON
            base.objtype = changes.objtype AND
            base.id = changes.id
    WHERE
        base.id IS NULL
)
DELETE FROM
    osm_changes AS changes
USING
    changes_without_base
WHERE
    changes_without_base.objtype = changes.objtype AND
    changes_without_base.id = changes.id
;

--DROP TABLE IF EXISTS base_update;
CREATE TABLE base_update AS
SELECT
    objtype,
    id,
    version
FROM
    osm_base
WHERE
    NOT (:osm_filter_tags)
;

--DROP TABLE IF EXISTS changes_update;
CREATE TEMP TABLE changes_update AS
WITH changes AS (
    SELECT
        *
    FROM
        osm_changes
    WHERE
        NOT (:osm_filter_tags)
)
SELECT DISTINCT ON (changes.objtype, changes.id)
    changes.*
FROM
    base_update AS base
    JOIN changes ON
        changes.objtype = base.objtype AND
        changes.id = base.id
ORDER BY
    changes.objtype,
    changes.id,
    changes.version DESC
;

DROP TABLE base_update;

DELETE FROM
    osm_base AS base
USING
    changes_update AS changes
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
    changes_update AS changes
WHERE
    changes.objtype = base.objtype AND
    changes.id = base.id AND
    NOT changes.deleted
;

DELETE FROM
    osm_changes AS changes
USING
    changes_update AS update
WHERE
    update.objtype = changes.objtype AND
    update.id = changes.id AND
    update.version >= changes.version
;

DROP TABLE changes_update;

COMMIT;
