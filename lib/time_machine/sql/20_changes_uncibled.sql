CREATE TEMP TABLE osm_changes_geom_proj AS
SELECT
    objtype,
    id,
    version,
    deleted,
    changeset_id,
    created,
    uid,
    username,
    tags,
    lon,
    lat,
    nodes,
    members,
    ST_Transform(ST_MakeValid(geom), :proj) AS geom,
    cibled
FROM osm_changes_geom;
ALTER TABLE osm_changes_geom_proj ADD PRIMARY KEY (objtype, id);

CREATE TEMP TABLE osm_changes_geom_part AS
SELECT
    objtype,
    id,
    ST_Subdivide(geom, 1000) AS geom_part
FROM
    osm_changes_geom_proj
;
CREATE INDEX osm_changes_geom_part_idx_geom ON osm_changes_geom_part USING GIST (geom_part);

CREATE TEMP VIEW osm_changes_geom_ AS
SELECT
    objtype,
    id,
    version,
    deleted,
    changeset_id,
    created,
    uid,
    username,
    tags,
    lon,
    lat,
    nodes,
    members,
    geom,
    geom_part,
    cibled
FROM
    osm_changes_geom_proj
    JOIN osm_changes_geom_part USING (objtype, id)
;

DROP TABLE IF EXISTS cibled_changes;
CREATE TEMP TABLE cibled_changes AS
WITH
clip AS (
    SELECT
        ST_Union(ST_GeomFromGeoJSON(geom)) AS geom,
        ST_MakeValid(ST_Transform(ST_Union(ST_GeomFromGeoJSON(geom)), :proj)) AS geom_proj
    FROM
        json_array_elements_text(:polygon::json) AS t(geom)
),
-- Select only objects of interest in the area from osm_base
cibled_base AS (
    SELECT
        objtype,
        id
    FROM
        osm_base AS _,
        clip
    WHERE
        (
            (:osm_filter_tags) AND
            (clip.geom IS NULL OR (clip.geom && _.geom AND ST_Intersects(clip.geom, ST_MakeValid(_.geom))))
        ) OR (
            _.geom IS NULL
        )
),
-- Select related changes linked to cibled_base
cibled_changes_from_base AS (
    SELECT
        changes.*
    FROM
        osm_changes_geom_proj AS changes
        JOIN cibled_base AS base ON
            base.objtype = changes.objtype AND
            base.id = changes.id
),
-- Select only object of interest in the area from osm_changes
cibled_changes AS (
    SELECT
        _.*
    FROM
        osm_changes_geom_proj AS _,
        clip
    WHERE
        (
            (:osm_filter_tags) AND
            (clip.geom IS NULL OR ST_Intersects(clip.geom_proj, _.geom))
        ) OR (
            _.geom IS NULL
        )
)
SELECT
    objtype,
    id,
    CASE WHEN base.nodes IS NOT NULL THEN cibled_changes.nodes || base.nodes ELSE cibled_changes.nodes END AS nodes,
    CASE WHEN base.members IS NOT NULL THEN cibled_changes.members || base.members ELSE cibled_changes.members END AS members,
    CASE WHEN base.geom IS NOT NULL THEN ST_Union(cibled_changes.geom, base.geom) ELSE cibled_changes.geom END AS geom
FROM
    cibled_changes
    LEFT JOIN cibled_changes_from_base AS base USING (objtype, id)

UNION ALL

SELECT
    objtype,
    id,
    base.nodes,
    base.members,
    base.geom
FROM
    cibled_changes_from_base AS base
    LEFT JOIN cibled_changes USING (objtype, id)
WHERE
    cibled_changes.id IS NULL
;
ALTER TABLE cibled_changes ADD PRIMARY KEY (objtype, id);

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
    SELECT * FROM cibled_changes
    UNION
    (
        WITH
        -- Recursive term should be referenced only once time
        b AS (SELECT * FROM a),

        by_geom AS (
        SELECT DISTINCT ON (other.objtype, other.id)
            other.objtype,
            other.id,
            other.nodes,
            other.members,
            other.geom
        FROM
            b AS cibled_changes
            JOIN osm_changes_geom_ AS other ON
                ST_DWithin(cibled_changes.geom, other.geom_part, :distance)
        ),

        nodes_to_ways AS (
        SELECT DISTINCT ON (ways.objtype, ways.id)
            ways.objtype,
            ways.id,
            ways.nodes,
            ways.members,
            ways.geom
        FROM
            b AS nodes
            JOIN osm_changes_geom_proj AS ways ON
                ways.objtype = 'w' AND
                nodes.id = ANY(ways.nodes)
        WHERE
            nodes.objtype = 'n'
        ),
        ways_to_nodes AS (
        SELECT DISTINCT ON (nodes.objtype, nodes.id)
            nodes.objtype,
            nodes.id,
            nodes.nodes,
            nodes.members,
            nodes.geom
        FROM
            b AS ways
            JOIN osm_changes_geom_proj AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = ANY(ways.nodes)
        WHERE
            ways.objtype = 'w'
        ),

        relations_to_nodes AS (
        SELECT DISTINCT ON (nodes.objtype, nodes.id)
            nodes.objtype,
            nodes.id,
            nodes.nodes,
            nodes.members,
            nodes.geom
        FROM
            b AS relations
            JOIN LATERAL jsonb_to_recordset(relations.members) AS relations_members(ref bigint, role text, type text) ON
                relations_members.type = 'n'
            JOIN osm_changes_geom_proj AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = relations_members.ref
        WHERE
            relations.objtype = 'r'
        ),
        relations_to_ways AS (
        SELECT DISTINCT ON (ways.objtype, ways.id)
            ways.objtype,
            ways.id,
            ways.nodes,
            ways.members,
            ways.geom
        FROM
            b AS relations
            JOIN LATERAL jsonb_to_recordset(relations.members) AS relations_members(ref bigint, role text, type text) ON
                relations_members.type = 'w'
            JOIN osm_changes_geom_proj AS ways ON
                ways.objtype = 'w' AND
                ways.id = relations_members.ref
        WHERE
            relations.objtype = 'r'
        ),
        nodes_or_ways_to_relations AS (
        SELECT DISTINCT ON (relations.objtype, relations.id)
            relations.objtype,
            relations.id,
            relations.nodes,
            relations.members,
            relations.geom
        FROM
            b AS nodes_or_ways
            JOIN osm_changes_geom_proj AS relations ON
                relations.objtype = 'r'
            JOIN LATERAL jsonb_to_recordset(relations.members) AS relations_members(ref bigint, role text, type text) ON
                relations_members.type = nodes_or_ways.objtype AND
                relations_members.ref = nodes_or_ways.id
        WHERE
            nodes_or_ways.objtype IN ('n', 'w')
        )
        SELECT * FROM by_geom
        UNION ALL
        SELECT * FROM nodes_to_ways
        UNION ALL
        SELECT * FROM ways_to_nodes
        UNION ALL
        SELECT * FROM relations_to_nodes
        UNION ALL
        SELECT * FROM relations_to_ways
        UNION ALL
        SELECT * FROM nodes_or_ways_to_relations
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

DROP TABLE osm_changes_geom_proj CASCADE;
DROP TABLE osm_changes_geom_part CASCADE;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cibled_changes & transitive: %', (SELECT COUNT(*) FROM cibled_changes);
END; $$ LANGUAGE plpgsql;

--- Select only changes not related to objects and area of interest, and not transitively related to them
DROP TABLE IF EXISTS changes_update;
CREATE TEMP TABLE changes_update AS
SELECT DISTINCT ON (osm_changes.id, osm_changes.objtype)
    osm_changes.*
FROM
    osm_changes
    LEFT JOIN cibled_changes AS cibled ON
        cibled.objtype = osm_changes.objtype AND
        cibled.id = osm_changes.id
WHERE
    cibled.objtype IS NULL
ORDER BY
    osm_changes.id,
    osm_changes.objtype
;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - changes_update: %', (SELECT COUNT(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;

DROP TABLE cibled_changes;
