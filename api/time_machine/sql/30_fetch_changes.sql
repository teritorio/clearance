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
            base.members,
            base.geom
        FROM
            osm_base AS base
            JOIN change_uniq ON
                change_uniq.objtype = base.objtype AND
                change_uniq.id = base.id
    ),
    state AS (
        SELECT
            *,
            coalesce(ST_HausdorffDistance(
                ST_Transform((first_value(geom) OVER (PARTITION BY objtype, id ORDER BY version)), 2154),
                ST_Transform(geom, 2154)
            ), 0) AS change_distance
        FROM (
                SELECT *, NULL::json AS changeset FROM base_i
                UNION ALL
                SELECT
                    osm_changes.*,
                    row_to_json(osm_changesets) AS changeset
                FROM
                    osm_changes_geom AS osm_changes
                    LEFT JOIN osm_changesets ON
                        osm_changesets.id = osm_changes.changeset_id
            ) AS t
        ORDER BY
            objtype,
            id,
            version,
            deleted DESC
    )
SELECT
    objtype,
    id,
    json_agg(row_to_json(state)::jsonb - 'objtype' - 'id' - 'uid' - 'geom' - 'nodes')::jsonb AS p
FROM
    state
GROUP BY
    objtype,
    id
ORDER BY
    objtype,
    id
;
