CREATE TEMP TABLE base_update AS
SELECT
    objtype,
    id,
    version
FROM
    osm_base
WHERE
    NOT (:osm_filter_tags)
;

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
