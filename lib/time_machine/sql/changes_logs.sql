SET search_path TO :"schema", public;

DROP FUNCTION IF EXISTS changes_logs();
CREATE OR REPLACE FUNCTION changes_logs() RETURNS TABLE(
    objects jsonb
) AS $$
    WITH
    validations_log AS (
        SELECT
            *
        FROM
            validations_log
        WHERE
            action IS NULL OR
            action = 'reject'
    ),
    features_uniq AS ((
        SELECT DISTINCT ON (validations_log.before_object->>'objtype', (validations_log.before_object->>'id')::bigint)
            validations_log.locha_id,
            validations_log.created,
            ST_Envelope(osm_base.geom) AS bbox,
            osm_base.changeset_id AS changeset_id,
            CASE WHEN osm_base.id is NOT NULL THEN jsonb_build_object(
                'type', 'Feature',
                'id', 'b' || osm_base.objtype || osm_base.id,
                'properties', jsonb_strip_nulls(jsonb_build_object(
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
                    'links', dense_rank() OVER (PARTITION BY validations_log.locha_id ORDER BY validations_log.semantic_group) - 1
                )),
                'geometry', ST_AsGeoJSON(osm_base.geom)::jsonb
            ) END AS feature
        FROM
            validations_log
            LEFT JOIN osm_base ON -- Allow NULL for coherent dense_rank
                osm_base.objtype = validations_log.before_object->>'objtype' AND
                osm_base.id = (validations_log.before_object->>'id')::bigint
        ORDER BY
            validations_log.before_object->>'objtype',
            (validations_log.before_object->>'id')::bigint
    ) UNION ALL (
        SELECT DISTINCT ON (validations_log.after_object->>'objtype', (validations_log.after_object->>'id')::bigint)
            validations_log.locha_id,
            validations_log.created,
            ST_Envelope(osm_changes.geom) AS bbox,
            osm_changes.changeset_id AS changeset_id,
            jsonb_build_object(
                'type', 'Feature',
                'id', 'a' || osm_changes.objtype || osm_changes.id,
                'properties', jsonb_strip_nulls(jsonb_build_object(
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
                    'links', dense_rank() OVER (PARTITION BY validations_log.locha_id ORDER BY validations_log.semantic_group) - 1
                )),
                'geometry', ST_AsGeoJSON(osm_changes.geom)::jsonb
            ) AS feature
        FROM
            validations_log
            LEFT JOIN osm_changes_geom AS osm_changes ON
                osm_changes.objtype = validations_log.after_object->>'objtype' AND
                osm_changes.id = (validations_log.after_object->>'id')::bigint AND
                osm_changes.version = (validations_log.after_object->>'version')::integer AND
                osm_changes.deleted = (validations_log.after_object->>'deleted')::boolean
        ORDER BY
            validations_log.after_object->>'objtype',
            (validations_log.after_object->>'id')::bigint
    )),
    features AS (
        SELECT
            locha_id,
            max(created) AS created,
            ST_Extent(bbox) AS bbox,
            jsonb_agg(feature) AS features
        FROM
            features_uniq
        WHERE
            feature IS NOT NULL
        GROUP BY
            locha_id
    ),
    links_uniq AS (
        SELECT
            locha_id,
            semantic_group,
            jsonb_agg(
                jsonb_strip_nulls(jsonb_build_object(
                    'matches', matches,
                    'action', action,
                    'before', 'b' || (before_object->>'objtype') || (before_object->>'id'),
                    'after', 'a' || (after_object->>'objtype') || (after_object->>'id'),
                    'diff_attribs', diff_attribs,
                    'diff_tags', diff_tags,
                    'conflation_reason', conflation
                ))
            ) AS link
        FROM
            validations_log
        GROUP BY
            locha_id,
            semantic_group
    ),
    links AS (
        SELECT
            locha_id,
            jsonb_agg(link ORDER BY semantic_group) AS links
        FROM
            links_uniq
        GROUP BY
            locha_id
    ),
    changesets_uniq AS (
        SELECT DISTINCT ON (features_uniq.locha_id, osm_changesets.id)
            features_uniq.locha_id,
            row_to_json(osm_changesets)::jsonb AS changeset
        FROM
            osm_changesets
            JOIN features_uniq ON
                osm_changesets.id = features_uniq.changeset_id
        ORDER BY
            features_uniq.locha_id,
            osm_changesets.id
    ),
    changesets AS (
        SELECT
            locha_id,
            jsonb_agg(changeset) AS changesets
        FROM
            changesets_uniq
        GROUP BY
            locha_id
    )
    SELECT
        jsonb_build_object(
            'type', 'FeatureCollection',
            'bbox', array[
                ST_YMin(bbox),
                ST_XMin(bbox),
                ST_YMax(bbox),
                ST_XMax(bbox)
            ],
            'features', features,
            'metadata', jsonb_build_object(
                'locha_id', locha_id,
                'links', links,
                'changesets', changesets
            )
        ) AS objects
    FROM
        features
        JOIN links USING (locha_id)
        LEFT JOIN changesets USING (locha_id)
    ORDER BY
        created
    ;
$$ LANGUAGE SQL PARALLEL SAFE;

COMMENT ON FUNCTION changes_logs IS
    'Changes to be reviewed';
