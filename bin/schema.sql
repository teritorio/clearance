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

DROP TABLE IF EXISTS osm_changesets CASCADE;
CREATE TABLE osm_changesets (
    id BIGINT NOT NULL,
    created_at TIMESTAMP (0) WITHOUT TIME ZONE NOT NULL,
    closed_at TIMESTAMP (0) WITHOUT TIME ZONE NOT NULL,
    open BOOLEAN NOT NULL,
    "user" TEXT NOT NULL,
    uid INTEGER NOT NULL,
    minlat REAL,
    minlon REAL,
    maxlat REAL,
    maxlon REAL,
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
ALTER TABLE osm_changes ADD PRIMARY KEY(id, objtype, version, deleted); -- %PK:osm_changes%

DROP TABLE IF EXISTS validations_log CASCADE;
CREATE TABLE validations_log (
    objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
    id BIGINT NOT NULL,
    version INTEGER NOT NULL,
    deleted BOOLEAN NOT NULL,
    changeset_ids INTEGER[] NOT NULL,
    created TIMESTAMP (0) WITHOUT TIME ZONE,
    matches JSONB NOT NULL,
    action TEXT,
    validator_uid INTEGER,
    diff_attribs JSONB,
    diff_tags JSONB
);
ALTER TABLE validations_log ADD PRIMARY KEY(id, objtype, version, deleted);

DROP TABLE IF EXISTS osm_changes_applyed CASCADE;
CREATE TABLE osm_changes_applyed AS
SELECT * FROM osm_changes
WITH NO DATA;
ALTER TABLE osm_changes_applyed ADD PRIMARY KEY(id, objtype, version, deleted); -- %PK:osm_changes_applyed%
