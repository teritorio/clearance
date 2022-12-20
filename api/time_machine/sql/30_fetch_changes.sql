WITH
    change_uniq AS (
        SELECT
            objtype,
            id
        FROM
            osm_changes
        GROUP BY
            objtype,
            id
    ),
    base_i AS (
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
            JOIN change_uniq ON
                change_uniq.objtype = base.objtype AND
                change_uniq.id = base.id
    ),
    state AS (
        SELECT
            *,
            coalesce(ST_Distance(
                ST_SetSRID(ST_MakePoint(
                    (first_value(lon) OVER (PARTITION BY objtype, id ORDER BY version))::real,
                    (first_value(lat) OVER (PARTITION BY objtype, id ORDER BY version))::real
                ), 4326)::geography,
                ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
            ), 0) AS change_distance
        FROM (
                SELECT * FROM base_i
                UNION
                SELECT * FROM osm_changes
            ) AS t
        ORDER BY
            objtype,
            id,
            version
    )
SELECT
    objtype,
    id,
    json_agg(row_to_json(state)::jsonb - 'objtype' - 'id')::jsonb AS p
FROM
    state
GROUP BY
    objtype,
    id
ORDER BY
    objtype,
    id
;
