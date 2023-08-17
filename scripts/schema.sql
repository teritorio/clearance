CREATE SCHEMA IF NOT EXISTS :schema;
SET search_path TO :schema,public;

DROP TABLE IF EXISTS osm_base CASCADE;
CREATE TABLE osm_base (
    objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')), -- %COL:osm_base:objtype%
    id BIGINT NOT NULL, -- %COL:osm_base:id%
    version INTEGER NOT NULL, -- %COL:osm_base:version%
    changeset_id INTEGER NOT NULL, -- %COL:osm_base:changeset_id%
    created TIMESTAMP (0) WITHOUT TIME ZONE, -- %COL:osm_base:created%
    uid INTEGER, -- %COL:osm_base:uid%
    username TEXT, -- %COL:osm_base:username%
    tags JSONB, -- %COL:osm_base:tags%
    lon REAL, -- %COL:osm_base:lon%
    lat REAL, -- %COL:osm_base:lat%
    nodes BIGINT[], -- %COL:osm_base:nodes%
    members JSONB -- %COL:osm_base:members%
);
ALTER TABLE osm_base ADD PRIMARY KEY(id, objtype); -- %PK:osm_base%
CREATE INDEX osm_base_idx_tags ON osm_base USING gin(tags);
CREATE INDEX osm_base_idx_nodes ON osm_base USING gin(nodes) WHERE objtype = 'w';

DROP TABLE IF EXISTS osm_changesets CASCADE;
CREATE TABLE osm_changesets (
    id BIGINT NOT NULL,
    created_at TIMESTAMP (0) WITHOUT TIME ZONE NOT NULL,
    closed_at TIMESTAMP (0) WITHOUT TIME ZONE NOT NULL,
    open BOOLEAN NOT NULL,
    user TEXT NOT NULL,
    uid INTEGER NOT NULL,
    minlat REAL NOT NULL,
    minlon REAL NOT NULL,
    maxlat REAL NOT NULL,
    maxlon REAL NOT NULL,
    comments_count INTEGER NOT NULL,
    changes_count INTEGER NOT NULL,
    tags JSONB NOT NULL
);
ALTER TABLE osm_changesets ADD PRIMARY KEY(id);

DROP TABLE IF EXISTS osm_changes CASCADE;
CREATE TABLE osm_changes (
    objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')), -- %COL:osm_changes:objtype%
    id BIGINT NOT NULL, -- %COL:osm_changes:id%
    version INTEGER NOT NULL, -- %COL:osm_changes:version%
    deleted BOOLEAN NOT NULL, -- %COL:osm_changes:deleted%
    changeset_id INTEGER NOT NULL, -- %COL:osm_changes:changeset_id%
    created TIMESTAMP (0) WITHOUT TIME ZONE, -- %COL:osm_changes:created%
    uid INTEGER, -- %COL:osm_changes:uid%
    username TEXT, -- %COL:osm_changes:username%
    tags JSONB, -- %COL:osm_changes:tags%
    lon REAL, -- %COL:osm_changes:lon%
    lat REAL, -- %COL:osm_changes:lat%
    nodes BIGINT[], -- %COL:osm_changes:nodes%
    members JSONB -- %COL:osm_changes:members%
);
ALTER TABLE osm_changes ADD PRIMARY KEY(id, objtype, version); -- %PK:osm_changes%

DROP TABLE IF EXISTS validations_log CASCADE;
CREATE TABLE validations_log (
    objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
    id BIGINT NOT NULL,
    version INTEGER NOT NULL,
    changeset_ids INTEGER[] NOT NULL,
    created TIMESTAMP (0) WITHOUT TIME ZONE,
    matches TEXT[] NOT NULL,
    action TEXT,
    validator_uid INTEGER,
    diff_attribs JSONB,
    diff_tags  JSONB
);
ALTER TABLE validations_log ADD PRIMARY KEY(id, objtype, version);

DROP TABLE IF EXISTS osm_changes_applyed CASCADE;
CREATE TABLE osm_changes_applyed AS
SELECT * FROM osm_changes
WITH NO DATA;
ALTER TABLE osm_changes_applyed ADD PRIMARY KEY(id, objtype, version); -- %PK:osm_changes_applyed%


CREATE OR REPLACE VIEW osm_base_nodes AS
SELECT
  id,
  version,
  created,
  tags,
  ST_MakePoint(lon, lat) AS geom
FROM
  osm_base
WHERE
  objtype = 'n'
;

CREATE TABLE osm_base_ways AS
SELECT
  ways.id,
  ways.version,
  ways.created,
  ways.tags,
  ST_MakeLine(nodes.geom ORDER BY way_nodes.index) AS geom
FROM
  osm_base AS ways
  JOIN LATERAL unnest(ways.nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON true
  JOIN osm_base_nodes AS nodes ON
    nodes.id = way_nodes.node_id
WHERE
  ways.objtype = 'w'
GROUP BY
  ways.id,
  ways.version,
  ways.created,
  ways.tags
;
ALTER TABLE osm_base_ways ADD PRIMARY KEY(id);
CREATE INDEX osm_base_ways_idx_tags ON osm_base_ways USING gin(tags);


DROP TRIGGER node_changes_ids_trigger ON node_changes_flag;
DROP TRIGGER node_changes_trigger ON osm_base;

CREATE TABLE IF NOT EXISTS node_changes_ids(
  id BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS node_changes_flag(
  flag text,
  UNIQUE (flag)
);

CREATE OR REPLACE FUNCTION node_changes_sotre() RETURNS trigger AS $$
BEGIN
  INSERT INTO node_changes_ids VALUES (NEW.id);
  INSERT INTO node_changes_flag VALUES (true) ON CONFLICT(flag) DO NOTHING;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION node_changes_ids_apply() RETURNS trigger AS $$
BEGIN
  WITH
  ways AS (
    SELECT DISTINCT ON (ways.id)
      ways.id,
      ways.nodes
    FROM
      node_changes_ids
      JOIN osm_base AS ways ON
        ways.objtype = 'w' AND
        ARRAY[node_changes_ids.id] <@ ways.nodes
    ORDER BY
      ways.id
    ),
  a AS (
    SELECT
      ways.id,
      ST_AsText(ST_MakeLine(nodes.geom ORDER BY way_nodes.index)) AS geom
    FROM
      ways
      JOIN LATERAL unnest(ways.nodes) WITH ORDINALITY AS way_nodes(node_id, index) ON true
      JOIN osm_base_nodes AS nodes ON
        nodes.id = way_nodes.node_id
    GROUP BY
      ways.id
  )
  UPDATE
    osm_base_ways
  SET
    geom = a.geom
  FROM
    a
  WHERE
    osm_base_ways.id = a.id
  ;

  DELETE FROM node_changes_ids;
  DELETE FROM node_changes_flag;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER node_changes_trigger
  AFTER INSERT OR UPDATE OF lat, lon
  ON osm_base
  FOR EACH ROW
  WHEN (NEW.objtype = 'n')
EXECUTE PROCEDURE node_changes_sotre();

CREATE CONSTRAINT TRIGGER node_changes_ids_trigger
  AFTER INSERT
  ON node_changes_flag
  INITIALLY DEFERRED
  FOR EACH ROW
EXECUTE PROCEDURE node_changes_ids_apply();


CREATE OR REPLACE VIEW osm_base_relations AS
SELECT
  relations.id,
  relations.version,
  relations.created,
  relations.tags,
  ST_LineMerge(ST_Collect(coalesce(osm_base_nodes.geom, osm_base_ways.geom))) AS geom
FROM
  osm_base AS relations
  JOIN LATERAL (
    SELECT
      *
    FROM
      jsonb_to_recordset(members) AS m(ref bigint, role text, type text)
  ) AS relations_members ON true
  LEFT JOIN osm_base_nodes ON
    osm_base_nodes.id = relations_members.ref
  LEFT JOIN osm_base_ways ON
    osm_base_ways.id = relations_members.ref
WHERE
  relations.objtype = 'r'
GROUP BY
  relations.id,
  relations.version,
  relations.created,
  relations.tags
;

CREATE OR REPLACE VIEW osm_base_areas AS
SELECT
  id,
  version,
  created,
  tags,
  ST_MakePolygon(geom) AS geom
FROM
  osm_base_relations
;
