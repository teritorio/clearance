SET search_path TO :"schema", public;

CREATE OR REPLACE FUNCTION array_min(anyarray)
RETURNS anyelement AS $$
  SELECT min(v) FROM unnest($1) v;
$$ LANGUAGE SQL PARALLEL SAFE IMMUTABLE;
CREATE OR REPLACE FUNCTION array_max(anyarray)
RETURNS anyelement AS $$
  SELECT max(v) FROM unnest($1) v;
$$ LANGUAGE SQL PARALLEL SAFE IMMUTABLE;


-- Triggers to update geom
DROP TRIGGER IF EXISTS osm_base_changes_ids_trigger ON osm_base_changes_flag;
DROP TRIGGER IF EXISTS osm_base_n_trigger_insert ON osm_base_n;
DROP TRIGGER IF EXISTS osm_base_w_trigger_insert ON osm_base_w;
DROP TRIGGER IF EXISTS osm_base_r_trigger_insert ON osm_base_r;
DROP TRIGGER IF EXISTS osm_base_n_trigger_update ON osm_base_n;
DROP TRIGGER IF EXISTS osm_base_w_trigger_update ON osm_base_w;
DROP TRIGGER IF EXISTS osm_base_r_trigger_update ON osm_base_r;


DO $$ BEGIN
    RAISE NOTICE 'schema_geom - osm_base_n';
END; $$ LANGUAGE plpgsql;

ALTER TABLE osm_base_n ADD COLUMN IF NOT EXISTS geom geometry(Geometry, 4326) NOT NULL GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED; -- Pass to VIRTUAL with Postgres 18
VACUUM FULL ANALYZE osm_base_n;
CREATE INDEX IF NOT EXISTS osm_base_n_idx_geom ON osm_base_n USING gist(geom);


-- Init geom, row by row to avoid peak disk usage

DO $$ BEGIN
    RAISE NOTICE 'schema_geom - osm_base_w';
END; $$ LANGUAGE plpgsql;

ALTER TABLE osm_base_w ADD COLUMN IF NOT EXISTS geom geometry(Geometry, 4326);
UPDATE
  osm_base_w
SET
  geom = (
    SELECT
      CASE
        WHEN ST_NPoints(ST_MakeLine(geom ORDER BY index)) = 1 THEN ST_PointN(ST_MakeLine(geom ORDER BY index), 1)
        ELSE ST_MakeLine(geom ORDER BY index)
      END AS geom
    FROM
      (
      SELECT
        way_nodes.index,
        CASE
          WHEN nodes.geom = lead(nodes.geom) OVER (ORDER BY way_nodes.index) THEN NULL
          ELSE nodes.geom
        END AS geom
      FROM
        unnest(osm_base_w.nodes) WITH ORDINALITY AS way_nodes(node_id, index)
        LEFT JOIN osm_base_n AS nodes ON
          nodes.id = way_nodes.node_id
      WHERE
        nodes.geom IS NOT NULL
      ) AS nodes
  )
;
VACUUM FULL ANALYZE osm_base_w;
CREATE INDEX IF NOT EXISTS osm_base_w_idx_nodes_gin ON osm_base_w USING gin(nodes);
CREATE INDEX IF NOT EXISTS osm_base_w_idx_nodes_gist ON osm_base_w USING gist(int8range(array_min(nodes), array_max(nodes), '[]'));
CREATE INDEX IF NOT EXISTS osm_base_w_idx_geom ON osm_base_w USING gist(geom);


DO $$ BEGIN
    RAISE NOTICE 'schema_geom - osm_base_r';
END; $$ LANGUAGE plpgsql;

ALTER TABLE osm_base_r ADD COLUMN IF NOT EXISTS geom geometry(Geometry, 4326);
UPDATE
  osm_base_r
SET
  geom = (
    SELECT
      ST_LineMerge(ST_Collect(coalesce(nodes.geom, ways.geom))) AS geom
    FROM
      jsonb_to_recordset(osm_base_r.members) AS relations_members(ref bigint, role text, type text)
      LEFT JOIN osm_base_n AS nodes ON
        relations_members.type = 'n' AND
        nodes.id = relations_members.ref
      LEFT JOIN osm_base_w AS ways ON
        relations_members.type = 'w' AND
        ways.id = relations_members.ref
  )
;
VACUUM FULL ANALYZE osm_base_r;
CREATE INDEX IF NOT EXISTS osm_base_r_idx_geom ON osm_base_r USING gist(geom);


DROP FUNCTION IF EXISTS osm_base_idx_nodes_members();
CREATE OR REPLACE FUNCTION osm_base_idx_nodes_members(
    _members jsonb,
    _type char(1)
) RETURNS bigint[] AS $$
  SELECT
    array_agg(id)
  FROM (
    SELECT
      (jsonb_array_elements(_members)->'ref')::bigint AS id,
      jsonb_array_elements(_members)->>'type' AS type
  ) AS t
  WHERE
    type = _type
;
$$ LANGUAGE SQL PARALLEL SAFE IMMUTABLE;

CREATE INDEX IF NOT EXISTS osm_base_idx_members_n ON osm_base_r USING gin(osm_base_idx_nodes_members(members, 'n'));
CREATE INDEX IF NOT EXISTS osm_base_idx_members_w ON osm_base_r USING gin(osm_base_idx_nodes_members(members, 'w'));
CREATE INDEX IF NOT EXISTS osm_base_idx_members_r ON osm_base_r USING gin(osm_base_idx_nodes_members(members, 'r'));


-- Drop triggers to update geom

CREATE TABLE IF NOT EXISTS osm_base_changes_ids(
  objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
  id BIGINT NOT NULL,
  UNIQUE (objtype, id)
);

CREATE TABLE IF NOT EXISTS osm_base_changes_flag(
  flag text,
  UNIQUE (flag)
);

CREATE OR REPLACE FUNCTION osm_base_n_log_update() RETURNS trigger AS $$
BEGIN
  INSERT INTO osm_base_changes_ids VALUES ('n', NEW.id) ON CONFLICT (objtype, id) DO NOTHING;
  INSERT INTO osm_base_changes_flag VALUES (true) ON CONFLICT (flag) DO NOTHING;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION osm_base_w_log_update() RETURNS trigger AS $$
BEGIN
  INSERT INTO osm_base_changes_ids VALUES ('w', NEW.id) ON CONFLICT (objtype, id) DO NOTHING;
  INSERT INTO osm_base_changes_flag VALUES (true) ON CONFLICT (flag) DO NOTHING;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION osm_base_r_log_update() RETURNS trigger AS $$
BEGIN
  INSERT INTO osm_base_changes_ids VALUES ('r', NEW.id) ON CONFLICT (objtype, id) DO NOTHING;
  INSERT INTO osm_base_changes_flag VALUES (true) ON CONFLICT (flag) DO NOTHING;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER osm_base_n_trigger_insert
  AFTER INSERT
  ON osm_base_n
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_n_log_update();

CREATE OR REPLACE TRIGGER osm_base_w_trigger_insert
  AFTER INSERT
  ON osm_base_w
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_w_log_update();

CREATE OR REPLACE TRIGGER osm_base_r_trigger_insert
  AFTER INSERT
  ON osm_base_r
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_r_log_update();

CREATE OR REPLACE TRIGGER osm_base_n_trigger_update
  AFTER UPDATE OF lon, lat
  ON osm_base_n
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_n_log_update();

CREATE OR REPLACE TRIGGER osm_base_w_trigger_update
  AFTER UPDATE
  ON osm_base_w
  FOR EACH ROW
  WHEN (OLD.nodes IS DISTINCT FROM NEW.nodes)
EXECUTE PROCEDURE osm_base_w_log_update();

CREATE OR REPLACE TRIGGER osm_base_r_trigger_update
  AFTER UPDATE
  ON osm_base_r
  FOR EACH ROW
  WHEN (OLD.members IS DISTINCT FROM NEW.members)
EXECUTE PROCEDURE osm_base_r_log_update();


CREATE OR REPLACE FUNCTION osm_base_update_geom() RETURNS trigger AS $$
BEGIN
  RAISE NOTICE 'schema_geom - osm_base_update_geom';

  DROP TABLE IF EXISTS node_groups;
  CREATE TEMP TABLE IF NOT EXISTS node_groups AS
  WITH numbered AS (
    SELECT
      id,
      row_number() OVER (ORDER BY id) / 100000 AS batch_num
    FROM
      osm_base_changes_ids
    WHERE
      objtype = 'n'
  )
  SELECT
    array_agg(id) AS ids
  FROM
    numbered
  GROUP BY
    batch_num
  ;

  DROP TABLE IF EXISTS way_groups;
  CREATE TEMP TABLE IF NOT EXISTS way_groups AS
  WITH numbered AS (
    SELECT
      id,
      row_number() OVER (ORDER BY id) / 100000 AS batch_num
    FROM
      osm_base_changes_ids
    WHERE
      objtype = 'w'
  )
  SELECT
    array_agg(id) AS ids
  FROM
    numbered
  GROUP BY
    batch_num
  ;
  RAISE NOTICE 'schema_geom - group changes ids';

  ANALYZE node_groups;
  ANALYZE way_groups;
  ANALYZE osm_base_w;
  RAISE NOTICE 'schema_geom - ANALYZE';

  -- Add transitive changes, from nodes to ways
  INSERT INTO osm_base_changes_ids
  SELECT DISTINCT ON (ways.id)
    'w' AS objtype,
    ways.id
  FROM
    node_groups
    JOIN osm_base_w AS ways ON
      node_groups.ids && ways.nodes
  ORDER BY
    ways.id
  ON CONFLICT (objtype, id) DO NOTHING
  ;
  RAISE NOTICE 'schema_geom - transitive changes nodes to ways';

  -- Add transitive changes, to relations
  INSERT INTO osm_base_changes_ids (
  SELECT DISTINCT ON (relations.id)
    'r' AS objtype,
    relations.id
  FROM
    node_groups
    JOIN osm_base_r AS relations ON
      node_groups.ids && osm_base_idx_nodes_members(members, 'n')
  ORDER BY
    relations.id

  ) UNION ALL (

  SELECT DISTINCT ON (relations.id)
    'r' AS objtype,
    relations.id
  FROM
    way_groups
    JOIN osm_base_r AS relations ON
      way_groups.ids && osm_base_idx_nodes_members(members, 'w')
  ORDER BY
    relations.id
  )
  ON CONFLICT (objtype, id) DO NOTHING
  ;
  RAISE NOTICE 'schema_geom - transitive changes nodes+ways to relations';

  DROP TABLE IF EXISTS node_groups;
  DROP TABLE IF EXISTS way_groups;

  WITH
  ways AS (
    SELECT
      ways.id,
      ways.nodes
    FROM
      osm_base_changes_ids
      JOIN osm_base_w AS ways ON
        ways.id = osm_base_changes_ids.id
    WHERE
      osm_base_changes_ids.objtype = 'w'
  ),
  a AS (
    SELECT
      ways.id,
      ST_RemoveRepeatedPoints(ST_MakeLine(geom ORDER BY index)) AS geom
    FROM
      ways
      LEFT JOIN LATERAL unnest(ways.nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON true
      LEFT JOIN osm_base_n AS nodes ON
        nodes.id = way_nodes.node_id
      WHERE
        nodes.geom IS NOT NULL
    GROUP BY
      ways.id
  )
  UPDATE
    osm_base_w
  SET
    geom = CASE
      WHEN ST_NPoints(a.geom) = 0 THEN NULL
      WHEN ST_NPoints(a.geom) = 1 THEN ST_PointN(a.geom, 1)
      WHEN ST_NPoints(a.geom) = 2 AND ST_PointN(a.geom, 1) = ST_PointN(a.geom, 2) THEN ST_PointN(a.geom, 1)
      ELSE a.geom
    END
  FROM
    a
  WHERE
    osm_base_w.id = a.id
  ;
  RAISE NOTICE 'schema_geom - update ways.geom';

  WITH
  relations AS (
    SELECT
      relations.id,
      relations.members
    FROM
      osm_base_changes_ids
      JOIN osm_base_r AS relations ON
        relations.id = osm_base_changes_ids.id
    WHERE
      osm_base_changes_ids.objtype = 'r'
  ),
  a AS (
    SELECT
      relations.id,
      ST_LineMerge(ST_Collect(coalesce(nodes.geom, ways.geom))) AS geom
    FROM
      relations
      JOIN LATERAL jsonb_to_recordset(members) AS relations_members(ref bigint, role text, type text) ON true
      LEFT JOIN osm_base_n AS nodes ON
        relations_members.type = 'n' AND
        nodes.id = relations_members.ref
      LEFT JOIN osm_base_w AS ways ON
        relations_members.type = 'w' AND
        ways.id = relations_members.ref
    GROUP BY
      relations.id
  )
  UPDATE
    osm_base_r
  SET
    geom = a.geom
  FROM
    a
  WHERE
    osm_base_r.id = a.id
  ;
  RAISE NOTICE 'schema_geom - update relations.geom';

  DELETE FROM osm_base_changes_ids;
  DELETE FROM osm_base_changes_flag;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER osm_base_changes_ids_trigger
  AFTER INSERT
  ON osm_base_changes_flag
  INITIALLY DEFERRED
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_update_geom();


CREATE OR REPLACE VIEW osm_base_areas AS
WITH
parts AS (
  SELECT
    id,
    version,
    created,
    tags,
    ST_LineMerge((ST_Dump(geom)).geom) AS geom
  FROM
    osm_base_r
),
poly AS (
  SELECT
    id,
    version,
    created,
    tags,
    CASE WHEN ST_IsValid(st_makepolygon(parts.geom))
      THEN ST_MakePolygon(geom)
    END AS geom
  FROM
    parts
  WHERE
    ST_NPoints(geom) >= 4 AND
    ST_IsClosed(geom)
)
SELECT
  id,
  version,
  created,
  tags,
  ST_Union(geom) AS geom
FROM
  poly
GROUP BY
  id,
  version,
  created,
  tags
;


CREATE OR REPLACE VIEW osm_base AS (
SELECT
    'n'::char(1) AS objtype,
    id,
    version,
    changeset_id,
    created,
    uid,
    username,
    tags,
    lon,
    lat,
    NULL::bigint[] AS nodes,
    NULL::jsonb AS members,
    geom
FROM
    osm_base_n

) UNION ALL (

SELECT
    'w' AS objtype,
    id,
    version,
    changeset_id,
    created,
    uid,
    username,
    tags,
    NULL AS lon,
    NULL AS lat,
    nodes,
    NULL::jsonb AS members,
    geom
FROM
    osm_base_w

) UNION ALL (

SELECT
    'r' AS objtype,
    id,
    version,
    changeset_id,
    created,
    uid,
    username,
    tags,
    NULL AS lon,
    NULL AS lat,
    NULL::bigint[] AS nodes,
    members,
    geom
FROM
    osm_base_r
);
