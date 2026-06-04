CREATE TEMP VIEW changes_source AS
SELECT
    changes.*
FROM
    changes_update AS update
    JOIN osm_changes AS changes USING (objtype, id)
;
