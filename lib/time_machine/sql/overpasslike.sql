CREATE OR REPLACE TEMP VIEW node AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'n' AS osm_type FROM osm_base_n;

CREATE OR REPLACE TEMP VIEW way AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, nodes, NULL::jsonb AS members, geom, 'w' AS osm_type FROM osm_base_w;

CREATE OR REPLACE TEMP VIEW relation AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, NULL::bigint[] AS nodes, members, geom, 'r' AS osm_type FROM osm_base_r;

CREATE OR REPLACE TEMP VIEW nwr AS
SELECT * FROM node
UNION ALL
SELECT * FROM way
UNION ALL
SELECT * FROM relation
;

CREATE INDEX IF NOT EXISTS osm_base_idx_id_36 ON osm_base_r((id+3600000000));
CREATE OR REPLACE TEMP VIEW area AS
SELECT id + 3600000000 AS id, version, NULL::integer AS changeset, created, tags, NULL::text AS user, NULL::integer AS uid, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'a' AS osm_type FROM osm_base_areas
UNION ALL
SELECT id, version, changeset_id AS changeset, created, tags, NULL::text AS user, uid, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'w' AS osm_type FROM osm_base_w WHERE ST_Dimension(geom) = 2
;
