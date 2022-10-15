WITH base_i AS (
    SELECT
        base.objtype,
        base.id,
        base.version,
        false AS deleted,
        base.changeset_id,
        base.created,
        base.uid,
        base.username,
        base.tags,
        base.lon,
        base.lat,
        base.nodes,
        base.members
    FROM
        osm_base AS base
        JOIN osm_changes AS changes ON
            changes.objtype = base.objtype AND
            changes.id = base.id
)
SELECT
    objtype,
    id,
    json_agg(row_to_json(t)::jsonb - 'objtype' - 'id')::jsonb AS p
FROM (
    SELECT * FROM base_i
    UNION
    SELECT * FROM osm_changes
) AS t
GROUP BY
    objtype,
    id
ORDER BY
    objtype,
    id
;
