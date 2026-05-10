DROP FUNCTION IF EXISTS unnest_unique(anycompatiblearray);
CREATE FUNCTION unnest_unique(anycompatiblearray) RETURNS TABLE(x anycompatible) AS $$
SELECT DISTINCT x FROM unnest($1) AS x
$$ LANGUAGE SQL PARALLEL SAFE IMMUTABLE;


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

CREATE TEMP TABLE changes_ AS
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
        _.tags,
        _.geom
    FROM
        clip,
        osm_changes_geom AS _
;
CREATE INDEX changes__idx_objtype_id ON changes_ (objtype, id);

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - changes_: %', (SELECT COUNT(*) FROM changes_);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE changes AS
WITH
changes_base AS (
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
)
SELECT
    row_number() OVER () AS cc_id,
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
    changes_base AS base
    JOIN changes_ AS changes USING (objtype, id)
;
ALTER TABLE changes ADD PRIMARY KEY (objtype, id);

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - changes: %', (SELECT COUNT(*) FROM changes);
END; $$ LANGUAGE plpgsql;


INSERT INTO changes
-- changes_with_base
SELECT
    coalesce((SELECT max(cc_id) FROM changes), 0) + row_number() OVER () AS cc_id,
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
    changes_ AS _
    LEFT JOIN osm_base AS base USING (objtype, id)
    LEFT JOIN changes USING (objtype, id)
WHERE
    changes.objtype IS NULL
;

DROP TABLE clip CASCADE;
DROP TABLE changes_ CASCADE;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - changes: %', (SELECT COUNT(*) FROM changes);
END; $$ LANGUAGE plpgsql;


-- Only keeps nodes and members that are in changes
WITH
deps AS (
    SELECT
        contact.objtype,
        contact.id,
        array_agg(nodes.id) FILTER (WHERE nodes.id IS NOT NULL) AS nodes,
        jsonb_agg(json_build_object('ref', contact_m.ref, 'role', contact_m.role, 'type', contact_m.type) ORDER BY contact_m.ref, contact_m.type) FILTER (WHERE members.id IS NOT NULL) AS members
    FROM
        changes AS contact
        LEFT JOIN LATERAL unnest_unique(contact.nodes) AS contact_nodes(id) ON
            contact.objtype = 'w'
        LEFT JOIN changes AS nodes ON
            nodes.objtype = 'n' AND
            nodes.id = contact_nodes.id
        LEFT JOIN LATERAL jsonb_to_recordset(contact.members) AS contact_m(ref bigint, role text, type text) ON
            contact.objtype = 'r'
        LEFT JOIN changes AS members ON
            members.objtype = contact_m.type AND
            members.id = contact_m.ref
    GROUP BY
        contact.objtype,
        contact.id
)
UPDATE
    changes
SET
    nodes = deps.nodes,
    members = deps.members
FROM
    deps
WHERE
    changes.objtype = deps.objtype AND
    changes.id = deps.id AND
    (
        changes.nodes IS DISTINCT FROM deps.nodes OR
        changes.members IS DISTINCT FROM deps.members
    )
;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - filter nodes and members changes: %', (SELECT COUNT(*) FROM changes);
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


-- Propagate cc_id to all connex components by topology
WITH RECURSIVE a AS (
    SELECT cc_id, objtype, id FROM changes
    UNION
    (
        WITH
        -- Recursive term should be referenced only once time
        b AS (
            SELECT
                a.cc_id,
                changes.objtype,
                changes.id,
                changes.nodes,
                changes.members
            FROM a
                JOIN changes USING (objtype, id)
        ),

        nodes_to_ways AS (
        SELECT
            least(min(nodes.cc_id), ways.cc_id) AS cc_id,
            ways.objtype,
            ways.id
        FROM
            b AS nodes
            JOIN changes AS ways ON
                ways.objtype = 'w' AND
                ways.nodes @> ARRAY[nodes.id]
        WHERE
            nodes.objtype = 'n'
        GROUP BY
            ways.cc_id,
            ways.objtype,
            ways.id
        ),
        ways_to_nodes AS (
        SELECT
            least(min(ways.cc_id), nodes.cc_id) AS cc_id,
            nodes.objtype,
            nodes.id
        FROM
            b AS ways
            JOIN LATERAL unnest(ways.nodes) AS node_id ON true
            JOIN changes AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = node_id
        WHERE
            ways.objtype = 'w'
        GROUP BY
            nodes.cc_id,
            nodes.objtype,
            nodes.id
        ),

        relations_to_nodes AS (
        SELECT
            least(min(relations.cc_id), nodes.cc_id) AS cc_id,
            nodes.objtype,
            nodes.id
        FROM
            b AS relations
            JOIN osm_changes_members AS m ON
                m.relation_id = relations.id AND
                m.type = 'n'
            JOIN changes AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = m.ref
        WHERE
            relations.objtype = 'r'
        GROUP BY
            nodes.cc_id,
            nodes.objtype,
            nodes.id
        ),
        relations_to_ways AS (
        SELECT
            least(min(relations.cc_id), ways.cc_id) AS cc_id,
            ways.objtype,
            ways.id
        FROM
            b AS relations
            JOIN osm_changes_members AS m ON
                m.relation_id = relations.id AND
                m.type = 'w'
            JOIN changes AS ways ON
                ways.objtype = 'w' AND
                ways.id = m.ref
        WHERE
            relations.objtype = 'r'
        GROUP BY
            ways.cc_id,
            ways.objtype,
            ways.id
        ),
        nodes_or_ways_to_relations AS (
        SELECT
            least(min(nodes_or_ways.cc_id), relations.cc_id) AS cc_id,
            relations.objtype,
            relations.id
        FROM
            b AS nodes_or_ways
            JOIN osm_changes_members AS m ON
                m.type IN ('n', 'w') AND
                m.type = nodes_or_ways.objtype AND
                m.ref = nodes_or_ways.id
            JOIN changes AS relations ON
                relations.objtype = 'r' AND
                relations.id = m.relation_id
        WHERE
            nodes_or_ways.objtype IN ('n', 'w')
        GROUP BY
            relations.cc_id,
            relations.objtype,
            relations.id
        )
        -- TODO relations to relations
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
),
min_cc_id AS (
    SELECT objtype, id, min(cc_id) AS cc_id FROM a GROUP BY objtype, id
)
UPDATE
    changes
SET
    cc_id = min_cc_id.cc_id
FROM
    min_cc_id
WHERE
    changes.objtype = min_cc_id.objtype AND
    changes.id = min_cc_id.id
;

DROP TABLE osm_changes_members CASCADE;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - connex components: %', (SELECT COUNT(DISTINCT cc_id) FROM changes);
END; $$ LANGUAGE plpgsql;


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
a AS (SELECT cc_id, bool_or(cibled) AS cibled, ST_Transform(ST_MakeValid(ST_Collect(geom)), :proj) AS geom_proj FROM changes GROUP BY cc_id),
b AS (SELECT cc_id, cibled, geom_proj, ST_SnapToGrid(ST_PointOnSurface(geom_proj), :distance * 100) AS snap_geom FROM a),
c AS (SELECT cc_id, cibled, geom_proj, cantor_pairing(ST_X(snap_geom)::bigint, ST_Y(snap_geom)::bigint) AS snap_grid_id FROM b),
d AS (SELECT cc_id, cibled, ST_ClusterWithinWin(geom_proj, :distance) OVER (PARTITION BY snap_grid_id) AS cluster_id FROM c),
e AS (SELECT cc_id, bool_or(cibled) OVER (PARTITION BY cluster_id) AS cibled, cluster_id FROM d)
SELECT cc_id FROM e WHERE cibled
;
CREATE INDEX changes_cluster_idx_cc_id ON changes_cluster (cc_id);

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cluster changes: %', (SELECT COUNT(*) FROM changes_cluster);
END; $$ LANGUAGE plpgsql;


-- Select only changes not related to objects and area of interest, and not transitively related to them
DROP TABLE IF EXISTS changes_update;
CREATE TEMP TABLE changes_update AS
SELECT
    osm_changes.*
FROM
    osm_changes
    JOIN changes ON
        changes.objtype = osm_changes.objtype AND
        changes.id = osm_changes.id
    LEFT JOIN changes_cluster ON
        changes_cluster.cc_id = changes.cc_id
WHERE
    changes_cluster.cc_id IS NULL
;

DROP TABLE changes;
DROP TABLE changes_cluster CASCADE;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - changes_update: %', (SELECT COUNT(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;
