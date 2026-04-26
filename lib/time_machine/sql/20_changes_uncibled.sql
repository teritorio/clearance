DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - osm_changes: %', (SELECT COUNT(*) FROM osm_changes);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE clip AS
    SELECT
        ST_MakeValid(ST_Union(ST_GeomFromGeoJSON(geom))) AS geom
    FROM
        json_array_elements_text(:polygon::json) AS t(geom)
;
ANALYZE clip;

CREATE TEMP TABLE osm_changes_geom_ AS
SELECT objtype, id, nodes, members, tags, geom FROM osm_changes_geom;
CREATE INDEX osm_changes_geom_idx_objtype_id ON osm_changes_geom_ (objtype, id);

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - persist osm_changes_geom: %', (SELECT COUNT(*) FROM osm_changes_geom_);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE changes AS
-- base_with_changes
WITH
base AS (
    SELECT
        _.objtype,
        _.id,
        coalesce(:osm_filter_tags, false) AND
        (
            _.geom IS NULL
            OR
            (clip.geom IS NULL OR ST_Intersects(clip.geom, _.geom))
        ) AS cibled,
        _.nodes,
        _.members,
        _.geom
    FROM
        clip,
        osm_base AS _
    WHERE
        _.geom IS NOT NULL AND
        (clip.geom IS NULL OR ST_Intersects(clip.geom, _.geom))
),
changes AS (
    SELECT
        _.objtype,
        _.id,
        coalesce(:osm_filter_tags, false) AND
        (
            _.geom IS NULL
            OR
            (clip.geom IS NULL OR ST_Intersects(clip.geom, _.geom))
        ) AS cibled,
        _.nodes,
        _.members,
        _.geom
    FROM
        clip,
        osm_changes_geom_ AS _
)
SELECT
    objtype,
    id,
    base.cibled OR changes.cibled AS cibled,
    base.nodes || changes.nodes AS nodes,
    base.members || changes.members AS members,
    ST_Union(
        coalesce(base.geom, ST_SetSRID('GEOMETRYCOLLECTION EMPTY'::geometry, 4326)),
        coalesce(changes.geom, ST_SetSRID('GEOMETRYCOLLECTION EMPTY'::geometry, 4326))
    ) AS geom
FROM
    clip,
    base
    JOIN changes USING (objtype, id)
;
ALTER TABLE changes ADD PRIMARY KEY (objtype, id);

INSERT INTO changes
-- changes_with_base
SELECT
    objtype,
    id,
    coalesce(:osm_filter_tags, false) AND
    (
        _.geom IS NULL
        OR
        (clip.geom IS NULL OR ST_Intersects(clip.geom, _.geom))
    ) AS cibled,
    CASE WHEN base.nodes IS NOT NULL THEN _.nodes || base.nodes ELSE _.nodes END AS nodes,
    CASE WHEN base.members IS NOT NULL THEN _.members || base.members ELSE _.members END AS members,
    CASE WHEN base.geom IS NOT NULL THEN ST_Union(_.geom, base.geom) ELSE _.geom END AS geom
FROM
    clip,
    osm_changes_geom_ AS _
    LEFT JOIN osm_base AS base USING (objtype, id)
    LEFT JOIN changes USING (objtype, id)
WHERE
    changes.objtype IS NULL
;

DROP TABLE clip CASCADE;
DROP TABLE osm_changes_geom_ CASCADE;

UPDATE osm_changes
SET cibled = changes.cibled
FROM changes
WHERE
    osm_changes.objtype = changes.objtype AND
    osm_changes.id = changes.id AND
    osm_changes.cibled IS DISTINCT FROM changes.cibled
;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cibled changes: % / %', (SELECT COUNT(*) FROM changes WHERE cibled), (SELECT COUNT(*) FROM changes);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE osm_changes_members AS
SELECT
    relations.id AS relation_id,
    m.ref,
    m.type
FROM
    changes AS relations
    JOIN LATERAL jsonb_to_recordset(relations.members) AS m(ref bigint, role text, type text) ON true
WHERE
    relations.objtype = 'r'
GROUP BY
    relations.id,
    m.ref,
    m.type
;
CREATE INDEX osm_changes_members_idx ON osm_changes_members (type, ref) WHERE type IN ('n', 'w');
CREATE INDEX osm_changes_members_relation_idx_n ON osm_changes_members (relation_id) WHERE type = 'n';
CREATE INDEX osm_changes_members_relation_idx_w ON osm_changes_members (relation_id) WHERE type = 'w';

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - index relation members: %', (SELECT COUNT(*) FROM osm_changes_members);
END; $$ LANGUAGE plpgsql;


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

CREATE TEMP TABLE changes_cluster AS
WITH
a AS (SELECT objtype, id, cibled, nodes, members, ST_Transform(ST_MakeValid(geom), :proj) AS geom_proj FROM changes),
b AS (SELECT objtype, id, cibled, nodes, members, geom_proj, ST_SnapToGrid(ST_PointOnSurface(geom_proj), :distance * 100) AS snap_geom FROM a),
c AS (SELECT objtype, id, cibled, nodes, members, geom_proj, cantor_pairing(ST_X(snap_geom)::bigint, ST_Y(snap_geom)::bigint) AS snap_grid_id FROM b)
SELECT
    objtype, id, cibled, nodes, members,
    snap_grid_id,
    ST_ClusterWithinWin(geom_proj, :distance) OVER (PARTITION BY snap_grid_id) AS cluster_id
FROM c
;
ALTER TABLE changes_cluster ADD PRIMARY KEY (objtype, id);
CREATE INDEX cibled_changes_cluster_idx_nodes ON changes_cluster USING GIN (nodes);
CREATE INDEX cibled_changes_cluster_idx_snap_grid_id_cluster_id ON changes_cluster (snap_grid_id, cluster_id);

DROP TABLE changes;

CREATE TEMP TABLE cibled_changes_cluster AS
SELECT * FROM changes_cluster WHERE cibled;
ALTER TABLE cibled_changes_cluster ADD PRIMARY KEY (objtype, id);

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cluster changes: %', (SELECT COUNT(*) FROM changes_cluster);
END; $$ LANGUAGE plpgsql;


-- Add transitive changes

INSERT INTO cibled_changes_cluster
WITH RECURSIVE a AS (
    SELECT * FROM cibled_changes_cluster
    UNION
    (
        WITH
        -- Recursive term should be referenced only once time
        b AS (SELECT * FROM a),

        by_geom AS (
        SELECT
            other.objtype,
            other.id,
            other.cibled,
            other.nodes,
            other.members,
            other.snap_grid_id,
            other.cluster_id
        FROM
            (SELECT snap_grid_id, cluster_id FROM b GROUP BY snap_grid_id, cluster_id) AS cluster_ids
            JOIN changes_cluster AS other ON
                other.snap_grid_id = cluster_ids.snap_grid_id AND
                other.cluster_id = cluster_ids.cluster_id
        ORDER BY
            other.objtype,
            other.id
        ),

        nodes_to_ways AS (
        SELECT
            ways.objtype,
            ways.id,
            ways.cibled,
            ways.nodes,
            ways.members,
            ways.snap_grid_id,
            ways.cluster_id
        FROM
            b AS nodes
            JOIN changes_cluster AS ways ON
                ways.objtype = 'w' AND
                ways.nodes @> ARRAY[nodes.id]
        WHERE
            nodes.objtype = 'n'
        ),
        ways_to_nodes AS (
        SELECT
            nodes.objtype,
            nodes.id,
            nodes.cibled,
            nodes.nodes,
            nodes.members,
            nodes.snap_grid_id,
            nodes.cluster_id
        FROM
            b AS ways
            JOIN changes_cluster AS nodes ON
                nodes.objtype = 'n' AND
                ways.nodes @> ARRAY[nodes.id]
        WHERE
            ways.objtype = 'w'
        ),

        relations_to_nodes AS (
        SELECT
            nodes.objtype,
            nodes.id,
            nodes.cibled,
            nodes.nodes,
            nodes.members,
            nodes.snap_grid_id,
            nodes.cluster_id
        FROM
            b AS relations
            JOIN osm_changes_members AS m ON
                m.relation_id = relations.id AND
                m.type = 'n'
            JOIN changes_cluster AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = m.ref
        WHERE
            relations.objtype = 'r'
        ),
        relations_to_ways AS (
        SELECT
            ways.objtype,
            ways.id,
            ways.cibled,
            ways.nodes,
            ways.members,
            ways.snap_grid_id,
            ways.cluster_id
        FROM
            b AS relations
            JOIN osm_changes_members AS m ON
                m.relation_id = relations.id AND
                m.type = 'w'
            JOIN changes_cluster AS ways ON
                ways.objtype = 'w' AND
                ways.id = m.ref
        WHERE
            relations.objtype = 'r'
        ),
        nodes_or_ways_to_relations AS (
        SELECT
            relations.objtype,
            relations.id,
            relations.cibled,
            relations.nodes,
            relations.members,
            relations.snap_grid_id,
            relations.cluster_id
        FROM
            b AS nodes_or_ways
            JOIN osm_changes_members AS m ON
                m.type IN ('n', 'w') AND
                m.type = nodes_or_ways.objtype AND
                m.ref = nodes_or_ways.id
            JOIN changes_cluster AS relations ON
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
SELECT DISTINCT * FROM a
ON CONFLICT DO NOTHING
;

DROP TABLE osm_changes_members CASCADE;
DROP TABLE changes_cluster CASCADE;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cibled_changes & transitive: %', (SELECT COUNT(*) FROM cibled_changes_cluster);
END; $$ LANGUAGE plpgsql;

-- Select only changes not related to objects and area of interest, and not transitively related to them
DROP TABLE IF EXISTS changes_update;
CREATE TEMP TABLE changes_update AS
SELECT DISTINCT ON (osm_changes.id, osm_changes.objtype)
    osm_changes.*
FROM
    osm_changes
    LEFT JOIN cibled_changes_cluster AS cibled ON
        cibled.objtype = osm_changes.objtype AND
        cibled.id = osm_changes.id
WHERE
    cibled.objtype IS NULL
ORDER BY
    osm_changes.id,
    osm_changes.objtype
;

DROP TABLE cibled_changes_cluster CASCADE;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - changes_update: %', (SELECT COUNT(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;
