SET search_path TO :schema,public;

ALTER TABLE osm_base ADD COLUMN IF NOT EXISTS geom geometry(Geometry, 4326);

CREATE INDEX IF NOT EXISTS osm_base_idx_nodes ON osm_base USING gin(nodes) WHERE objtype = 'w';

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

CREATE INDEX osm_base_idx_members_n ON osm_base USING gin(osm_base_idx_nodes_members(members, 'n')) WHERE objtype = 'r';
CREATE INDEX osm_base_idx_members_w ON osm_base USING gin(osm_base_idx_nodes_members(members, 'w')) WHERE objtype = 'r';


-- Trigger to update geom
DROP TRIGGER IF EXISTS osm_base_changes_ids_trigger ON osm_base_changes_flag;
DROP TRIGGER IF EXISTS osm_base_nodes_trigger ON osm_base;
DROP TRIGGER IF EXISTS osm_base_trigger_insert ON osm_base;
DROP TRIGGER IF EXISTS osm_base_trigger_update ON osm_base;

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

  INSERT INTO osm_base_changes_ids VALUES (NEW.objtype, NEW.id) ON CONFLICT (objtype, id) DO NOTHING;
  INSERT INTO osm_base_changes_flag VALUES (true) ON CONFLICT (flag) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER osm_base_nodes_trigger
  BEFORE INSERT OR UPDATE OF lon, lat
  ON osm_base
  FOR EACH ROW
  WHEN (NEW.objtype = 'n')
EXECUTE PROCEDURE osm_base_nodes_geom();

CREATE OR REPLACE FUNCTION osm_base_log_update() RETURNS trigger AS $$
BEGIN
  INSERT INTO osm_base_changes_ids VALUES (NEW.objtype, NEW.id) ON CONFLICT (objtype, id) DO NOTHING;
  INSERT INTO osm_base_changes_flag VALUES (true) ON CONFLICT (flag) DO NOTHING;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER osm_base_trigger_insert
  AFTER INSERT
  ON osm_base
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_log_update();

CREATE TRIGGER osm_base_trigger_update
  AFTER UPDATE
  ON osm_base
  FOR EACH ROW
  WHEN (OLD.nodes IS DISTINCT FROM NEW.nodes OR OLD.members IS DISTINCT FROM NEW.members)
EXECUTE PROCEDURE osm_base_log_update();

CREATE OR REPLACE FUNCTION osm_base_update_geom() RETURNS trigger AS $$
BEGIN
  -- Add transitive changes, from nodes to ways
  INSERT INTO osm_base_changes_ids
  SELECT DISTINCT ON (ways.id)
    ways.objtype,
    ways.id
  FROM
    osm_base_changes_ids
    JOIN osm_base AS ways ON
      ways.objtype = 'w' AND
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
    relations.objtype,
    relations.id
  FROM
    osm_base_changes_ids
    JOIN osm_base AS relations ON
      relations.objtype = 'r' AND
      ARRAY[osm_base_changes_ids.id] @> (osm_base_idx_nodes_members(members, 'n'))
  WHERE
    osm_base_changes_ids.objtype = 'n'
  ORDER BY
    relations.id

  ) UNION ALL (

  SELECT DISTINCT ON (relations.id)
    relations.objtype,
    relations.id
  FROM
    osm_base_changes_ids
    JOIN osm_base AS relations ON
      relations.objtype = 'r' AND
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
      JOIN osm_base AS ways ON
        ways.objtype = 'w' AND
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
      JOIN osm_base AS nodes ON
        nodes.objtype = 'n' AND
        nodes.id = way_nodes.node_id
    GROUP BY
      ways.id
  )
  UPDATE
    osm_base
  SET
    geom = a.geom
  FROM
    a
  WHERE
    osm_base.objtype = 'w' AND
    osm_base.id = a.id
  ;

  WITH
  relations AS (
    SELECT
      relations.id,
      relations.members
    FROM
      osm_base_changes_ids
      JOIN osm_base AS relations ON
        relations.objtype = 'r' AND
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
      LEFT JOIN osm_base AS nodes ON
        nodes.objtype = 'n' AND
        nodes.id = relations_members.ref
      LEFT JOIN osm_base AS ways ON
        ways.objtype = 'w' AND
        ways.id = relations_members.ref
    GROUP BY
      relations.id
  )
  UPDATE
    osm_base
  SET
    geom = a.geom
  FROM
    a
  WHERE
    osm_base.objtype = 'r' AND
    osm_base.id = a.id
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
    osm_base
  WHERE
    objtype = 'r'
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

UPDATE osm_base SET geom=ST_MakePoint(lon, lat) WHERE objtype='n';

CREATE TEMP TABLE osm_base_geom_way AS
SELECT
  ways.id,
  ST_MakeLine(nodes.geom ORDER BY way_nodes.index) AS geom
FROM
  osm_base AS ways
  JOIN LATERAL unnest(ways.nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON true
  JOIN osm_base AS nodes ON
    nodes.objtype = 'n' AND
    nodes.id = way_nodes.node_id
WHERE
  ways.objtype = 'w'
GROUP BY
  ways.id
;
UPDATE
  osm_base
SET
  geom = osm_base_geom_way.geom
FROM
  osm_base_geom_way
WHERE
  osm_base.objtype = 'w' AND
  osm_base.id = osm_base_geom_way.id
;
DROP TABLE osm_base_geom_way;

WITH a AS (
  SELECT
    relations.id,
    ST_LineMerge(ST_Collect(coalesce(nodes.geom, ways.geom))) AS geom
  FROM
    osm_base AS relations
    JOIN LATERAL jsonb_to_recordset(members) AS relations_members(ref bigint, role text, type text) ON true
    LEFT JOIN osm_base AS nodes ON
      nodes.objtype = 'n' AND
      nodes.id = relations_members.ref
    LEFT JOIN osm_base AS ways ON
      ways.objtype = 'w' AND
      ways.id = relations_members.ref
  WHERE
    ways.objtype = 'w'
  GROUP BY
    relations.id
)
UPDATE
  osm_base
SET
  geom = a.geom
FROM
  a
WHERE
  osm_base.objtype = 'r' AND
  osm_base.id = a.id
;

CREATE INDEX osm_base_idx_geom ON osm_base USING gist(geom);
