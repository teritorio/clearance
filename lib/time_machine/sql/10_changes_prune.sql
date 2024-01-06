WITH changes_delete_without_base AS (
    SELECT
        changes.objtype,
        changes.id
    FROM
        osm_changes AS changes
        LEFT JOIN osm_base AS base ON
            base.objtype = changes.objtype AND
            base.id = changes.id
    WHERE
        changes.deleted AND
        base.id IS NULL
)
DELETE FROM
    osm_changes AS changes
USING
    changes_delete_without_base
WHERE
    changes_delete_without_base.objtype = changes.objtype AND
    changes_delete_without_base.id = changes.id
;
