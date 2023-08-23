SET search_path TO :schema,public;

DROP FUNCTION IF EXISTS changes_logs();
CREATE OR REPLACE FUNCTION changes_logs() RETURNS TABLE(
    objtype character(1),
    id bigint,
    base json,
    change json,
    changesets json,
    matches text[],
    action text,
    diff_attribs json,
    diff_tags json
) AS $$
    SELECT
        osm_base.objtype,
        osm_base.id,
        json_build_object(
            'version', osm_base.version,
            'changeset_id', osm_base.changeset_id,
            'created', osm_base.created,
            'uid', osm_base.uid,
            'username', osm_base.username,
            'tags', osm_base.tags,
            'lon', osm_base.lon,
            'lat', osm_base.lat,
            'deleted', false,
            'members', osm_base.members,
            'geom', ST_AsGeoJSON(osm_base.geom)::json
        ) AS base,
        json_build_object(
            'version', osm_changes.version,
            'changeset_id', osm_changes.changeset_id,
            'created', osm_changes.created,
            'uid', osm_changes.uid,
            'username', osm_changes.username,
            'tags', osm_changes.tags,
            'lon', osm_changes.lon,
            'lat', osm_changes.lat,
            'deleted', osm_changes.deleted,
            'members', osm_changes.members,
            'geom', ST_AsGeoJSON(osm_changes.geom)::json
        ) AS change,
        (
            SELECT json_agg(j) FROM (
                SELECT
                    row_to_json(osm_changesets) AS j
                FROM
                    osm_changesets
                WHERE
                    osm_changesets.id = osm_base.changeset_id OR
                    osm_changesets.id = ANY(validations_log.changeset_ids)
                ORDER BY
                    osm_changesets.created_at
            ) AS t
        ) AS changesets,
        validations_log.matches,
        validations_log.action,
        validations_log.diff_attribs,
        validations_log.diff_tags
    FROM
        validations_log
        JOIN osm_base ON
            osm_base.objtype = validations_log.objtype AND
            osm_base.id = validations_log.id
        JOIN osm_changes_geom AS osm_changes ON
            osm_changes.objtype = validations_log.objtype AND
            osm_changes.id = validations_log.id AND
            osm_changes.version = validations_log.version AND
            osm_changes.deleted = validations_log.deleted
    WHERE
        action IS NULL OR
        action = 'reject'
    ORDER BY
        osm_changes.changeset_id,
        osm_changes.created,
        osm_changes.objtype,
        osm_changes.id,
        osm_changes.version
    ;
$$ LANGUAGE SQL PARALLEL SAFE;

COMMENT ON FUNCTION changes_logs IS
    'Changes to be reviewed';
