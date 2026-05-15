DROP FUNCTION IF EXISTS unnest_unique(anycompatiblearray);
CREATE FUNCTION unnest_unique(anycompatiblearray) RETURNS TABLE(x anycompatible) AS $$
SELECT DISTINCT x FROM unnest($1) AS x
$$ LANGUAGE SQL PARALLEL SAFE IMMUTABLE;


ANALYZE osm_changes;

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
        _.deleted,
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
ANALYZE changes_;
CREATE INDEX changes__idx_objtype_id ON changes_ (objtype, id);

DO $$ BEGIN
    assert (SELECT COUNT(*) FROM changes_) = (SELECT COUNT(*) FROM osm_changes), 'changes_ should have the same number of rows as osm_changes';
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
    changes.deleted AS cc_propa,
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
-- changes without base
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
    true AS cc_propa,
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
    assert (SELECT COUNT(*) FROM changes) = (SELECT COUNT(*) FROM osm_changes), 'changes should have the same number of rows as osm_changes';
    RAISE NOTICE '20_changes_uncibled - changes: %', (SELECT COUNT(*) FROM changes);
END; $$ LANGUAGE plpgsql;


CREATE TEMP TABLE osm_changes_members AS
SELECT
    relations.id AS relation_id,
    m.ref,
    m.type
FROM
    changes AS relations
    JOIN LATERAL jsonb_to_recordset(relations.members) AS m(ref bigint, role text, type text) ON true
    JOIN changes AS members ON
        members.objtype = m.type AND
        members.id = m.ref
WHERE
    relations.objtype = 'r'
;
CREATE INDEX osm_changes_members_idx ON osm_changes_members (type, ref) WHERE type IN ('n', 'w');
CREATE INDEX osm_changes_members_relation_idx_n ON osm_changes_members (relation_id) WHERE type = 'n';
CREATE INDEX osm_changes_members_relation_idx_w ON osm_changes_members (relation_id) WHERE type = 'w';

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - index relation members: %', (SELECT COUNT(*) FROM osm_changes_members);
END; $$ LANGUAGE plpgsql;


-- Forward cc_propa from nodes up to ways
WITH
nodes_ids AS (
    SELECT
        changes.id,
        unnest_unique(changes.nodes) AS nid
    FROM
        changes
    WHERE
        objtype = 'w' AND
        NOT cc_propa
)
UPDATE
    changes
SET
    cc_propa = true
FROM
    nodes_ids
    JOIN changes AS nodes ON
        nodes.objtype = 'n' AND
        nodes.id = nodes_ids.nid AND
        nodes.cc_propa
WHERE
    changes.objtype = 'w' AND
    NOT changes.cc_propa AND
    changes.id = nodes_ids.id
;

-- Forward cc_propa from any objects up to relations
UPDATE
    changes
SET
    cc_propa = true
FROM
    osm_changes_members AS m
    JOIN changes AS deps ON
        deps.objtype = m.type AND
        deps.id = m.ref AND
        deps.cc_propa
WHERE
    changes.objtype = 'r' AND
    NOT changes.cc_propa AND
    m.relation_id = changes.id
;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - forward cc_propa w: %', (SELECT COUNT(*) FROM changes WHERE cc_propa AND objtype = 'w');
    RAISE NOTICE '20_changes_uncibled - forward cc_propa r: %', (SELECT COUNT(*) FROM changes WHERE cc_propa AND objtype = 'r');
END; $$ LANGUAGE plpgsql;


-- initial_cc_id is used as a "pointer" for path compression.
-- cc_id decreases monotonically; for any X with cc_id=C, the object Z that
-- originally had cc_id=C (Z.initial_cc_id=C) may have since been merged to
-- a lower value, letting X skip ahead in O(log D) steps instead of O(D).
UPDATE changes SET cc_id = cc_id * CASE WHEN cc_propa THEN 1 ELSE -1 END;
ALTER TABLE changes ADD COLUMN initial_cc_id bigint;
UPDATE changes SET initial_cc_id = cc_id;
CREATE INDEX changes_idx_initial_cc_id ON changes (initial_cc_id);
CREATE INDEX changes_idx_cc_id ON changes (cc_id);
ANALYZE changes;

-- Propagate cc_id to all connex components by topology
DO $$
DECLARE cnt int := (SELECT COUNT(*) FROM changes WHERE cc_id >= 0);
BEGIN
  WHILE cnt > 0 LOOP
    -- One hop: propagate the minimum cc_id through all connection types
    WITH updates AS (
        -- nodes_to_ways: update ways based on member nodes
        SELECT
            min(nodes.cc_id) AS min_cc_id,
            ways.objtype,
            ways.id
        FROM
            changes AS ways
            JOIN LATERAL unnest_unique(ways.nodes) AS node_id ON true
            JOIN changes AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = node_id AND
                nodes.cc_id >= 0
        WHERE
            ways.objtype = 'w' AND
            ways.cc_id >= 0
        GROUP BY
            ways.objtype,
            ways.id
        HAVING
            min(nodes.cc_id) < ways.cc_id

        UNION ALL

        -- ways_to_nodes: update nodes based on containing ways
        SELECT
            min(ways.cc_id) AS min_cc_id,
            nodes.objtype,
            nodes.id
        FROM
            changes AS ways
            JOIN LATERAL unnest_unique(ways.nodes) AS node_id ON true
            JOIN changes AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = node_id AND
                nodes.cc_id >= 0
        WHERE
            ways.objtype = 'w' AND
            ways.cc_id >= 0
        GROUP BY
            nodes.objtype,
            nodes.id
        HAVING
            min(ways.cc_id) < nodes.cc_id

        UNION ALL

        -- relations_to_nodes: update nodes based on containing relations
        SELECT
            min(relations.cc_id) AS min_cc_id,
            nodes.objtype,
            nodes.id
        FROM
            changes relations
            JOIN osm_changes_members m ON
                m.relation_id = relations.id AND
                m.type = 'n'
            JOIN changes AS nodes ON
                nodes.objtype = 'n' AND
                nodes.id = m.ref AND
                nodes.cc_id >= 0
        WHERE
            relations.objtype = 'r' AND
            relations.cc_id >= 0
        GROUP BY
            nodes.objtype,
            nodes.id
        HAVING
            min(relations.cc_id) < nodes.cc_id

        UNION ALL

        -- relations_to_ways: update ways based on containing relations
        SELECT
            min(relations.cc_id) AS min_cc_id,
            ways.objtype,
            ways.id
        FROM
            changes AS relations
            JOIN osm_changes_members AS m ON
                m.relation_id = relations.id AND
                m.type = 'w'
            JOIN changes AS ways ON
                ways.objtype = 'w' AND
                ways.id = m.ref AND
                ways.cc_id >= 0
        WHERE
            relations.objtype = 'r' AND
            relations.cc_id >= 0
        GROUP BY
            ways.objtype,
            ways.id
        HAVING
            min(relations.cc_id) < ways.cc_id

        UNION ALL

        -- nodes_or_ways_to_relations: update relations based on contained nodes/ways
        SELECT
            min(nodes_or_ways.cc_id) AS min_cc_id,
            relations.objtype,
            relations.id
        FROM
            changes AS nodes_or_ways
            JOIN osm_changes_members AS m ON
                m.type IN ('n', 'w') AND
                m.type = nodes_or_ways.objtype AND
                m.ref = nodes_or_ways.id
            JOIN changes AS relations ON
                relations.objtype = 'r' AND
                relations.id = m.relation_id AND
                relations.cc_id >= 0
        WHERE
            nodes_or_ways.objtype IN ('n', 'w') AND
            nodes_or_ways.cc_id >= 0
        GROUP BY
            relations.objtype,
            relations.id
        HAVING
            min(nodes_or_ways.cc_id) < relations.cc_id

        -- TODO relations to relations
    ),
    best AS (
        SELECT objtype, id, MIN(min_cc_id) AS min_cc_id FROM updates GROUP BY objtype, id
    )
    UPDATE changes
    SET cc_id = best.min_cc_id
    FROM best
    WHERE
        changes.objtype = best.objtype AND
        changes.id = best.id AND
        best.min_cc_id < changes.cc_id
    ;

    GET DIAGNOSTICS cnt = ROW_COUNT;

    -- Full path compression: for each cc_id value C that objects point to,
    -- follow the chain initial_cc_id=C → cc_id → ... recursively until the
    -- minimum is reached, then update all pointers in one shot.
    -- Termination is guaranteed because cc_id strictly decreases and is
    -- bounded below by 1.
    WITH RECURSIVE
    chase AS (
        SELECT
            cc_id AS target,
            cc_id AS root
        FROM
            changes
        WHERE
            cc_id >= 0
        UNION ALL
        SELECT
            c.target,
            z.cc_id
        FROM
            chase AS c
            JOIN changes AS z ON
                z.initial_cc_id = c.root AND
                z.cc_id < c.root AND
                z.cc_id >= 0
    ),
    compressed AS (
        SELECT target, MIN(root) AS root FROM chase GROUP BY target
    )
    UPDATE changes AS x
    SET cc_id = compressed.root
    FROM compressed
    WHERE
        x.cc_id = compressed.target AND
        x.cc_id >= 0 AND
        compressed.root < x.cc_id
    ;

    -- Keep initial_cc_id in sync so the next iteration's chase starts from
    -- up-to-date pointers, not stale intermediate chain nodes.
    UPDATE changes SET initial_cc_id = cc_id WHERE initial_cc_id != cc_id AND cc_id >= 0;

    RAISE NOTICE '20_changes_uncibled - connex components propagation iteration, updated % rows', cnt;
  END LOOP;
END $$ LANGUAGE plpgsql;

DROP TABLE osm_changes_members CASCADE;
ALTER TABLE changes DROP COLUMN initial_cc_id;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - connex components: %', (SELECT COUNT(DISTINCT cc_id) FROM changes);
END; $$ LANGUAGE plpgsql;


UPDATE osm_changes SET cc_id = NULL;
UPDATE
    osm_changes
SET
    cibled = changes.cibled,
    cc_id = changes.cc_id
FROM
    changes
WHERE
    osm_changes.objtype = changes.objtype AND
    osm_changes.id = changes.id
;

DO $$ BEGIN
    RAISE NOTICE '20_changes_uncibled - cibled changes: % / %', (SELECT COUNT(*) FROM changes WHERE cibled), (SELECT COUNT(*) FROM changes);
    assert (SELECT COUNT(*) FROM osm_changes WHERE cc_id IS NULL) = 0, 'cc_id should not be null';
    RAISE NOTICE '20_changes_uncibled - largest connex components size: %', (SELECT array_agg(n) FROM (SELECT count(*) FROM osm_changes GROUP BY cc_id ORDER BY count(*) DESC LIMIT 10) AS t(n));
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
