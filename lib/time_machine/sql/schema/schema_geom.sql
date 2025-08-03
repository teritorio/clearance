SET search_path TO :schema,public;

ALTER TABLE osm_base_n ADD COLUMN IF NOT EXISTS geom geometry(Geometry, 4326);
ALTER TABLE osm_base_w ADD COLUMN IF NOT EXISTS geom geometry(Geometry, 4326);
ALTER TABLE osm_base_r ADD COLUMN IF NOT EXISTS geom geometry(Geometry, 4326);

CREATE INDEX IF NOT EXISTS osm_base_w_idx_nodes ON osm_base_w USING gin(nodes);

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


-- Trigger to update geom
DROP TRIGGER IF EXISTS osm_base_changes_ids_trigger ON osm_base_changes_flag;
DROP TRIGGER IF EXISTS osm_base_nodes_trigger ON osm_base_n;
DROP TRIGGER IF EXISTS osm_base_trigger_insert ON osm_base_n;
DROP TRIGGER IF EXISTS osm_base_trigger_update ON osm_base_n;

CREATE TABLE IF NOT EXISTS osm_base_changes_ids(
  objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
  id BIGINT NOT NULL,
  UNIQUE (objtype, id)
);

CREATE TABLE IF NOT EXISTS osm_base_changes_flag(
  flag text,
  UNIQUE (flag)
);

CREATE OR REPLACE FUNCTION osm_base_nodes_geom() RETURNS trigger AS $$
BEGIN
  NEW.geom := ST_MakePoint(NEW.lon, NEW.lat);

  INSERT INTO osm_base_changes_ids VALUES ('n', NEW.id) ON CONFLICT (objtype, id) DO NOTHING;
  INSERT INTO osm_base_changes_flag VALUES (true) ON CONFLICT (flag) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER osm_base_nodes_trigger
  BEFORE INSERT OR UPDATE OF lon, lat
  ON osm_base_n
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_nodes_geom();

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

CREATE OR REPLACE TRIGGER osm_base_trigger_insert
  AFTER INSERT
  ON osm_base_n
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_n_log_update();

CREATE OR REPLACE TRIGGER osm_base_trigger_insert
  AFTER INSERT
  ON osm_base_w
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_w_log_update();
CREATE OR REPLACE TRIGGER osm_base_trigger_insert
  AFTER INSERT
  ON osm_base_r
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_r_log_update();

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
  -- Add transitive changes, from nodes to ways
  INSERT INTO osm_base_changes_ids
  SELECT DISTINCT ON (ways.id)
    'w' AS objtype,
    ways.id
  FROM
    osm_base_changes_ids
    JOIN osm_base_w AS ways ON
      ARRAY[osm_base_changes_ids.id] <@ ways.nodes
  WHERE
    osm_base_changes_ids.objtype = 'n'
  ORDER BY
    ways.id
  ON CONFLICT (objtype, id) DO NOTHING
  ;

  -- Add transitive changes, to relations
  INSERT INTO osm_base_changes_ids (
  SELECT DISTINCT ON (relations.id)
    'r' AS objtype,
    relations.id
  FROM
    osm_base_changes_ids
    JOIN osm_base_r AS relations ON
      ARRAY[osm_base_changes_ids.id] @> (osm_base_idx_nodes_members(members, 'n'))
  WHERE
    osm_base_changes_ids.objtype = 'n'
  ORDER BY
    relations.id

  ) UNION ALL (

  SELECT DISTINCT ON (relations.id)
    'r' AS objtype,
    relations.id
  FROM
    osm_base_changes_ids
    JOIN osm_base_r AS relations ON
      ARRAY[osm_base_changes_ids.id] @> (osm_base_idx_nodes_members(members, 'w'))
  WHERE
    osm_base_changes_ids.objtype = 'w'
  ORDER BY
    relations.id
  )
  ON CONFLICT (objtype, id) DO NOTHING
  ;

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
      ST_MakeLine(nodes.geom ORDER BY way_nodes.index) AS geom
    FROM
      ways
      JOIN LATERAL unnest(ways.nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON true
      JOIN osm_base_n AS nodes ON
        nodes.id = way_nodes.node_id
    GROUP BY
      ways.id
  )
  UPDATE
    osm_base_w
  SET
    geom = a.geom
  FROM
    a
  WHERE
    osm_base_w.id = a.id
  ;

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
    ST_MakePolygon(geom) AS geom
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


-- Init geom

UPDATE osm_base_n SET geom=ST_MakePoint(lon, lat);

CREATE TEMP TABLE osm_base_geom_way AS
SELECT
  ways.id,
  ST_MakeLine(nodes.geom ORDER BY way_nodes.index) AS geom
FROM
  osm_base_w AS ways
  JOIN LATERAL unnest(ways.nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON true
  JOIN osm_base_n AS nodes ON
    nodes.id = way_nodes.node_id
GROUP BY
  ways.id
;
UPDATE
  osm_base_w
SET
  geom = osm_base_geom_way.geom
FROM
  osm_base_geom_way
WHERE
  osm_base_w.id = osm_base_geom_way.id
;
DROP TABLE osm_base_geom_way;

WITH a AS (
  SELECT
    relations.id,
    ST_LineMerge(ST_Collect(coalesce(nodes.geom, ways.geom))) AS geom
  FROM
    osm_base_r AS relations
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

CREATE INDEX IF NOT EXISTS osm_base_n_idx_geom ON osm_base_n USING gist(geom);
CREATE INDEX IF NOT EXISTS osm_base_w_idx_geom ON osm_base_w USING gist(geom);
CREATE INDEX IF NOT EXISTS osm_base_r_idx_geom ON osm_base_r USING gist(geom);

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
