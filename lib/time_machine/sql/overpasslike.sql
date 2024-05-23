CREATE OR REPLACE TEMP VIEW node AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'n';

CREATE OR REPLACE TEMP VIEW way AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, nodes, NULL::jsonb AS members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'w';

CREATE OR REPLACE TEMP VIEW relation AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, NULL::bigint[] AS nodes, members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'r';

CREATE OR REPLACE TEMP VIEW nwr AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, nodes, members, geom, objtype AS osm_type FROM osm_base;

CREATE INDEX IF NOT EXISTS osm_base_idx_id_36 ON osm_base((id+3600000000)) WHERE objtype = 'r';
CREATE OR REPLACE TEMP VIEW area AS
SELECT id + 3600000000 AS id, version, NULL::integer AS changeset, created, tags, NULL::text AS user, NULL::integer AS uid, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'a' AS osm_type FROM osm_base_areas
UNION ALL
SELECT id, version, changeset_id AS changeset, created, tags, NULL::text AS user, uid, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'w' AS osm_type FROM osm_base WHERE objtype = 'w' AND ST_Dimension(geom) = 2
;
