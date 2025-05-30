CREATE TEMP TABLE osm_changes_geom_ AS
SELECT * FROM osm_changes_geom;
CREATE INDEX osm_changes_geom_idx_geom ON osm_changes_geom_ USING GIST (geom);


DROP TABLE IF EXISTS cibled_changes;
CREATE TEMP TABLE cibled_changes AS
WITH
clip AS (
    SELECT
        ST_Union(ST_GeomFromGeoJSON(geom)) AS geom
    FROM
        json_array_elements_text(:polygon::json) AS t(geom)
),
-- Select only objects of interest in the area from osm_base
cibled_base AS (
    SELECT
        objtype,
        id
    FROM
        osm_base,
        clip
    WHERE
        (
            (:osm_filter_tags) AND
            (clip.geom IS NULL OR ST_Intersects(clip.geom, osm_base.geom))
        ) OR (
            osm_base.geom IS NULL
        )
),
-- Select related changes liked to cibled_base
cibled_changes_from_base AS (
    SELECT
        changes.*
    FROM
        osm_changes_geom_ AS changes
        JOIN cibled_base AS base ON
            base.objtype = changes.objtype AND
            base.id = changes.id
),
-- Select only object of interest in the area from osm_changes
cibled_changes AS (
    SELECT
        osm_changes_geom_.*
    FROM
        osm_changes_geom_,
        clip
    WHERE
        (
            (:osm_filter_tags) AND
            (clip.geom IS NULL OR ST_Intersects(clip.geom, osm_changes_geom_.geom))
        ) OR (
            osm_changes_geom_.geom IS NULL
        )
)
SELECT DISTINCT ON (changes.objtype, changes.id)
    *
FROM (
    SELECT
        cibled_changes_from_base.*
    FROM
        cibled_changes_from_base
    UNION ALL
    SELECT
        cibled_changes.*
    FROM
        cibled_changes
) AS changes
ORDER BY
    changes.objtype,
    changes.id
;

UPDATE osm_changes
SET cibled = false
WHERE cibled != false
;

UPDATE osm_changes
SET cibled = true
FROM cibled_changes
WHERE
    osm_changes.objtype = cibled_changes.objtype AND
    osm_changes.id = cibled_changes.id
;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cibled_changes: %', (SELECT COUNT(*) FROM cibled_changes);
    RAISE NOTICE '20_changes_uncibled - osm_changes: % (cibled: %, not cibled: %)', (SELECT COUNT(*) FROM osm_changes), (SELECT COUNT(*) FROM osm_changes WHERE cibled), (SELECT COUNT(*) FROM osm_changes WHERE NOT cibled);
END; $$ LANGUAGE plpgsql;


-- Add transitive changes

INSERT INTO cibled_changes
WITH RECURSIVE a AS (
    SELECT
        objtype,
        id,
        version,
        false AS deleted,
        changeset_id,
        created,
        uid,
        username,
        tags,
        lon,
        lat,
        nodes,
        members,
        geom
    FROM
        cibled_changes
    UNION
    (
        WITH b AS (
            -- Recursive term should be referenced only once time
            SELECT * FROM a
        )
        (
        SELECT
            ways.objtype,
            ways.id,
            ways.version,
            false AS deleted,
            ways.changeset_id,
            ways.created,
            ways.uid,
            ways.username,
            ways.tags,
            ways.lon,
            ways.lat,
            ways.nodes,
            ways.members,
            ways.geom
        FROM
            b AS cibled_changes
            JOIN osm_changes_geom_ AS ways ON
                ways.objtype = 'w' AND
                ST_DWithin(cibled_changes.geom, ways.geom, :distance)
        WHERE
            cibled_changes.objtype = 'n'

        ) UNION (

        SELECT
            relations.objtype,
            relations.id,
            relations.version,
            false AS deleted,
            relations.changeset_id,
            relations.created,
            relations.uid,
            relations.username,
            relations.tags,
            relations.lon,
            relations.lat,
            relations.nodes,
            relations.members,
            relations.geom
        FROM
            b AS cibled_changes
            JOIN osm_changes_geom_ AS relations ON
                relations.objtype = 'r' AND
                ST_DWithin(cibled_changes.geom, relations.geom, :distance)
        WHERE
            cibled_changes.objtype = 'n'

        ) UNION (

        SELECT
            relations.objtype,
            relations.id,
            relations.version,
            false AS deleted,
            relations.changeset_id,
            relations.created,
            relations.uid,
            relations.username,
            relations.tags,
            relations.lon,
            relations.lat,
            relations.nodes,
            relations.members,
            relations.geom
        FROM
            b AS cibled_changes
            JOIN osm_changes_geom_ AS relations ON
                relations.objtype = 'r' AND
                ST_DWithin(cibled_changes.geom, relations.geom, :distance)
        WHERE
            cibled_changes.objtype = 'w'
        )
    )
)
SELECT DISTINCT ON (objtype, id)
    *
FROM
    a
ORDER BY
    objtype,
    id
ON CONFLICT DO NOTHING
;

DROP TABLE osm_changes_geom_;

--- Select only changes not related to objects and area of interest, and not transitively related to them
DROP TABLE IF EXISTS changes_update;
CREATE TEMP TABLE changes_update AS
SELECT DISTINCT ON (osm_changes.objtype, osm_changes.id)
    osm_changes.*
FROM
    osm_changes
    LEFT JOIN cibled_changes AS cibled ON
        cibled.objtype = osm_changes.objtype AND
        cibled.id = osm_changes.id
WHERE
    cibled.objtype IS NULL
ORDER BY
    osm_changes.objtype,
    osm_changes.id
;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cibled_changes & transitive: %', (SELECT COUNT(*) FROM cibled_changes);
    RAISE NOTICE '20_changes_uncibled - changes_update: %', (SELECT COUNT(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;

DROP TABLE cibled_changes;
