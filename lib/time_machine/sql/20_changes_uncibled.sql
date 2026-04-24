-- Match grid cells to pairs of integers using Cantor pairing
DROP FUNCTION IF EXISTS cantor_pairing CASCADE;
CREATE FUNCTION cantor_pairing(x bigint, y bigint) RETURNS bigint AS $$
DECLARE
    a bigint := CASE WHEN x >= 0 THEN 2*x ELSE -2*x - 1 END;
    b bigint := CASE WHEN y >= 0 THEN 2*y ELSE -2*y - 1 END;
BEGIN
  RETURN (a + b) * (a + b + 1) / 2 + b;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE TEMP TABLE osm_changes_geom_proj AS
WITH
a AS (SELECT objtype, id, version, deleted, tags, nodes, members, locha_id, ST_Transform(ST_MakeValid(geom), :proj) AS geom FROM osm_changes_geom),
b AS (SELECT objtype, id, version, deleted, tags, nodes, members, locha_id, geom, ST_SnapToGrid(ST_PointOnSurface(geom), :distance * 100) AS snap_geom FROM a),
c AS (SELECT objtype, id, version, deleted, tags, nodes, members, locha_id, cantor_pairing(ST_X(snap_geom)::bigint, ST_Y(snap_geom)::bigint) AS snap_grid_id, geom FROM b)
SELECT
    objtype, id, version, deleted, tags, nodes, members, locha_id,
    snap_grid_id,
    ST_ClusterWithinWin(geom, :distance) OVER (PARTITION BY snap_grid_id) AS cluster_id,
    geom
FROM c
;
ALTER TABLE osm_changes_geom_proj ADD PRIMARY KEY (objtype, id);
CREATE INDEX osm_changes_geom_proj_idx_nodes ON osm_changes_geom_proj USING GIN (nodes);
CREATE INDEX osm_changes_geom_proj_idx_snap_grid_id_cluster_id ON osm_changes_geom_proj (snap_grid_id, cluster_id);

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - reproject and cluster changes: %', (SELECT COUNT(*) FROM osm_changes_geom_proj);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE osm_changes_members AS
SELECT
    relations.id AS relation_id,
    m.ref,
    m.type
FROM
    osm_changes_geom_proj AS relations
    JOIN LATERAL jsonb_to_recordset(relations.members) AS m(ref bigint, role text, type text) ON true
WHERE
    relations.objtype = 'r'
;
CREATE INDEX osm_changes_members_idx ON osm_changes_members (type, ref) WHERE type IN ('n', 'w');
CREATE INDEX osm_changes_members_relation_idx_n ON osm_changes_members (relation_id) WHERE type = 'n';
CREATE INDEX osm_changes_members_relation_idx_w ON osm_changes_members (relation_id) WHERE type = 'w';

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - index relation members: %', (SELECT COUNT(*) FROM osm_changes_members);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE clip AS
    SELECT
        ST_Union(ST_GeomFromGeoJSON(geom)) AS geom,
        ST_MakeValid(ST_Transform(ST_Union(ST_GeomFromGeoJSON(geom)), :proj)) AS geom_proj
    FROM
        json_array_elements_text(:polygon::json) AS t(geom)
;

CREATE TEMP TABLE cibled_changes_from_base AS
WITH
-- Select only objects of interest in the area from osm_base
cibled_base AS (
    SELECT
        objtype,
        id
    FROM
        osm_base AS _,
        clip
    WHERE
        (:osm_filter_tags) AND
        (
            _.geom IS NULL
            OR
            (clip.geom IS NULL OR (clip.geom && _.geom AND ST_Intersects(clip.geom, ST_MakeValid(_.geom))))
        )
)
-- Select related changes linked to cibled_base
    SELECT
        changes.*
    FROM
        osm_changes_geom_proj AS changes
        JOIN cibled_base AS base ON
            base.objtype = changes.objtype AND
            base.id = changes.id
;
CREATE INDEX cibled_changes_from_base_idx ON cibled_changes_from_base (objtype, id);

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - fetch cibled changes from base: %', (SELECT COUNT(*) FROM cibled_changes_from_base);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE cibled_changes_0 AS
-- Select only object of interest in the area from osm_changes
    SELECT
        _.*
    FROM
        osm_changes_geom_proj AS _,
        clip
    WHERE
        (:osm_filter_tags) AND
        (
            _.geom IS NULL
            OR
            (clip.geom IS NULL OR ST_Intersects(clip.geom_proj, _.geom))
        )
;
CREATE INDEX cibled_changes_0_idx ON cibled_changes_0 (objtype, id);

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - fetch cibled changes: %', (SELECT COUNT(*) FROM cibled_changes_0);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE cibled_changes AS
SELECT
    objtype,
    id,
    cibled_changes.snap_grid_id,
    cibled_changes.cluster_id,
    CASE WHEN base.nodes IS NOT NULL THEN cibled_changes.nodes || base.nodes ELSE cibled_changes.nodes END AS nodes,
    CASE WHEN base.members IS NOT NULL THEN cibled_changes.members || base.members ELSE cibled_changes.members END AS members,
    CASE WHEN base.geom IS NOT NULL THEN ST_Union(cibled_changes.geom, base.geom) ELSE cibled_changes.geom END AS geom
FROM
    cibled_changes_0 AS cibled_changes
    LEFT JOIN cibled_changes_from_base AS base USING (objtype, id)

UNION ALL

SELECT
    objtype,
    id,
    base.snap_grid_id,
    base.cluster_id,
    base.nodes,
    base.members,
    base.geom
FROM
    cibled_changes_from_base AS base
    LEFT JOIN cibled_changes_0 AS cibled_changes USING (objtype, id)
WHERE
    cibled_changes.id IS NULL
;
ALTER TABLE cibled_changes ADD PRIMARY KEY (objtype, id);

DROP TABLE clip CASCADE;
DROP TABLE cibled_changes_from_base CASCADE;
DROP TABLE cibled_changes_0 CASCADE;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cibled changes union: %', (SELECT COUNT(*) FROM cibled_changes);
END; $$ LANGUAGE plpgsql;


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
        SELECT
            other.objtype,
            other.id,
            other.snap_grid_id,
            other.cluster_id,
            other.nodes,
            other.members,
            other.geom
        FROM
            (SELECT snap_grid_id, cluster_id FROM b GROUP BY snap_grid_id, cluster_id) AS cibled_changes
            JOIN osm_changes_geom_proj AS other ON
                other.snap_grid_id = cibled_changes.snap_grid_id AND
                other.cluster_id = cibled_changes.cluster_id
        ORDER BY
            other.objtype,
            other.id
        ),

        nodes_to_ways AS (
        SELECT
            ways.objtype,
            ways.id,
            ways.snap_grid_id,
            ways.cluster_id,
            ways.nodes,
            ways.members,
            ways.geom
        FROM
            b AS nodes
            JOIN osm_changes_geom_proj AS ways ON
                ways.objtype = 'w' AND
                ways.nodes @> ARRAY[nodes.id]
        WHERE
            nodes.objtype = 'n'
        ),
        ways_to_nodes AS (
        SELECT
            nodes.objtype,
            nodes.id,
            nodes.snap_grid_id,
            nodes.cluster_id,
            nodes.nodes,
            nodes.members,
            nodes.geom
        FROM
            b AS ways
            JOIN osm_changes_geom_proj AS nodes ON
                nodes.objtype = 'n' AND
                ways.nodes @> ARRAY[nodes.id]
        WHERE
            ways.objtype = 'w'
        ),

        relations_to_nodes AS (
        SELECT
            nodes.objtype,
            nodes.id,
            nodes.snap_grid_id,
            nodes.cluster_id,
            nodes.nodes,
            nodes.members,
            nodes.geom
        FROM
            b AS relations
            JOIN osm_changes_members AS m ON
                m.relation_id = relations.id AND
                m.type = 'n'
            JOIN osm_changes_geom_proj AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = m.ref
        WHERE
            relations.objtype = 'r'
        ),
        relations_to_ways AS (
        SELECT
            ways.objtype,
            ways.id,
            ways.snap_grid_id,
            ways.cluster_id,
            ways.nodes,
            ways.members,
            ways.geom
        FROM
            b AS relations
            JOIN osm_changes_members AS m ON
                m.relation_id = relations.id AND
                m.type = 'w'
            JOIN osm_changes_geom_proj AS ways ON
                ways.objtype = 'w' AND
                ways.id = m.ref
        WHERE
            relations.objtype = 'r'
        ),
        nodes_or_ways_to_relations AS (
        SELECT
            relations.objtype,
            relations.id,
            relations.snap_grid_id,
            relations.cluster_id,
            relations.nodes,
            relations.members,
            relations.geom
        FROM
            b AS nodes_or_ways
            JOIN osm_changes_members AS m ON
                m.type IN ('n', 'w') AND
                m.type = nodes_or_ways.objtype AND
                m.ref = nodes_or_ways.id
            JOIN osm_changes_geom_proj AS relations ON
                relations.objtype = 'r' AND
                relations.id = m.relation_id
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
DROP TABLE osm_changes_members CASCADE;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cibled_changes & transitive: %', (SELECT COUNT(*) FROM cibled_changes);
END; $$ LANGUAGE plpgsql;

-- Select only changes not related to objects and area of interest, and not transitively related to them
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
