CREATE SCHEMA IF NOT EXISTS :schema;

DROP TABLE IF EXISTS :schema."osm_base" CASCADE;
CREATE TABLE :schema."osm_base" (
    "objtype" CHAR(1) CHECK(objtype IN ('n', 'w', 'r')), -- %COL:osm_base:objtype%
    "id" BIGINT NOT NULL, -- %COL:osm_base:id%
    "version" INTEGER NOT NULL, -- %COL:osm_base:version%
    "changeset_id" INTEGER NOT NULL, -- %COL:osm_base:changeset_id%
    "created" TIMESTAMP (0) WITHOUT TIME ZONE, -- %COL:osm_base:created%
    "uid" INTEGER, -- %COL:osm_base:uid%
    "username" TEXT, -- %COL:osm_base:username%
    "tags" JSONB, -- %COL:osm_base:tags%
    "lon" REAL, -- %COL:osm_base:lon%
    "lat" REAL, -- %COL:osm_base:lat%
    "nodes" BIGINT[], -- %COL:osm_base:nodes%
    "members" JSONB -- %COL:osm_base:members%
);
ALTER TABLE :schema."osm_base" ADD PRIMARY KEY(id, objtype); -- %PK:osm_base%

DROP TABLE IF EXISTS :schema."osm_changes" CASCADE;
CREATE TABLE :schema."osm_changes" (
    "objtype" CHAR(1) CHECK(objtype IN ('n', 'w', 'r')), -- %COL:osm_changes:objtype%
    "id" BIGINT NOT NULL, -- %COL:osm_changes:id%
    "version" INTEGER NOT NULL, -- %COL:osm_changes:version%
    "deleted" BOOLEAN NOT NULL, -- %COL:osm_changes:deleted%
    "changeset_id" INTEGER NOT NULL, -- %COL:osm_changes:changeset_id%
    "created" TIMESTAMP (0) WITHOUT TIME ZONE, -- %COL:osm_changes:created%
    "uid" INTEGER, -- %COL:osm_changes:uid%
    "username" TEXT, -- %COL:osm_changes:username%
    "tags" JSONB, -- %COL:osm_changes:tags%
    "lon" REAL, -- %COL:osm_changes:lon%
    "lat" REAL, -- %COL:osm_changes:lat%
    "nodes" BIGINT[], -- %COL:osm_changes:nodes%
    "members" JSONB -- %COL:osm_changes:members%
);
ALTER TABLE :schema."osm_changes" ADD PRIMARY KEY(id, objtype, version); -- %PK:osm_changes%

DROP TABLE IF EXISTS :schema."validations_log" CASCADE;
CREATE TABLE :schema."validations_log" (
    "objtype" CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
    "id" BIGINT NOT NULL,
    "version" INTEGER NOT NULL,
    "changeset_id" INTEGER NOT NULL,
    "created" TIMESTAMP (0) WITHOUT TIME ZONE,
    "uid" INTEGER,
    "username" TEXT,
    "action" TEXT,
    "validator_uid" INTEGER,
    "diff_attribs" JSONB,
    "diff_tags"  JSONB
);
ALTER TABLE :schema."validations_log" ADD PRIMARY KEY(id, objtype, version);

DROP TABLE IF EXISTS :schema."osm_changes_applyed" CASCADE;
CREATE TABLE :schema."osm_changes_applyed" AS
SELECT * FROM :schema."osm_changes"
WITH NO DATA;
ALTER TABLE :schema."osm_changes_applyed" ADD PRIMARY KEY(id, objtype, version); -- %PK:osm_changes_applyed%
