CREATE TEMP VIEW changes_source AS
SELECT
    changes.*
FROM
    changes_update AS update
    JOIN osm_changes AS changes ON
        changes.objtype = update.objtype AND
        changes.id = update.id AND
        changes.version = update.version AND
        changes.deleted = update.deleted
;
