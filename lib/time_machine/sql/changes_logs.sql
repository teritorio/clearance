SET search_path TO :schema,public;

DROP FUNCTION IF EXISTS changes_logs();
CREATE OR REPLACE FUNCTION changes_logs() RETURNS TABLE(
    id bigint,
    objects jsonb
) AS $$
    WITH objects AS (
    SELECT
        validations_log.locha_id,
        CASE WHEN osm_base.id is NOT NULL THEN jsonb_build_object(
            'objtype', osm_base.objtype,
            'id', osm_base.id,
            'version', osm_base.version,
            'changeset_id', osm_base.changeset_id,
            'created', osm_base.created,
            'uid', osm_base.uid,
            'username', osm_base.username,
            'tags', osm_base.tags,
            'deleted', false,
            'members', osm_base.members,
            'geom', ST_AsGeoJSON(osm_base.geom)::jsonb
        ) END AS base,
        jsonb_build_object(
            'objtype', osm_changes.objtype,
            'id', osm_changes.id,
            'version', osm_changes.version,
            'changeset_id', osm_changes.changeset_id,
            'created', osm_changes.created,
            'uid', osm_changes.uid,
            'username', osm_changes.username,
            'tags', osm_changes.tags,
            'deleted', osm_changes.deleted,
            'members', osm_changes.members,
            'geom', ST_AsGeoJSON(osm_changes.geom)::jsonb
        ) AS change,
        (
            SELECT jsonb_agg(j) FROM (
                SELECT
                    row_to_json(osm_changesets)::jsonb AS j
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
        LEFT JOIN osm_base ON
            osm_base.objtype = validations_log.before_object->>'objtype' AND
            osm_base.id = (validations_log.before_object->>'id')::bigint
        LEFT JOIN osm_changes_geom AS osm_changes ON
            osm_changes.objtype = validations_log.after_object->>'objtype' AND
            osm_changes.id = (validations_log.after_object->>'id')::bigint AND
            osm_changes.version = (validations_log.after_object->>'version')::integer AND
            osm_changes.deleted = (validations_log.after_object->>'deleted')::boolean
    WHERE
        action IS NULL OR
        action = 'reject'
    ORDER BY
        validations_log.locha_id,
        osm_changes.created
    )
    SELECT
        locha_id,
        jsonb_agg(
            row_to_json(objects)::jsonb - 'locha_id'
            ORDER BY change->>'created'
        )::jsonb
    FROM
        objects
    GROUP BY
        locha_id
    ORDER BY
        max(change->>'created')
    ;
$$ LANGUAGE SQL PARALLEL SAFE;

COMMENT ON FUNCTION changes_logs IS
    'Changes to be reviewed';
