CREATE OR REPLACE TEMP VIEW node_by_geom AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'n' AS osm_type FROM osm_base_n;
CREATE OR REPLACE TEMP VIEW node_by_id AS SELECT * FROM node_by_geom;

CREATE OR REPLACE TEMP VIEW way_by_geom AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, nodes, NULL::jsonb AS members, geom, 'w' AS osm_type FROM osm_base_w;
CREATE OR REPLACE TEMP VIEW way_by_id AS SELECT * FROM way_by_geom;

CREATE OR REPLACE TEMP VIEW relation_by_geom AS
SELECT id, version, changeset_id AS changeset, created, NULL::text AS user, uid, tags, NULL::bigint[] AS nodes, members, geom, 'r' AS osm_type FROM osm_base_r;
CREATE OR REPLACE TEMP VIEW relation_by_id AS SELECT * FROM relation_by_geom;

CREATE OR REPLACE TEMP VIEW nwr_by_geom AS
SELECT * FROM node_by_geom
UNION ALL
SELECT * FROM way_by_geom
UNION ALL
SELECT * FROM relation_by_geom
;
CREATE OR REPLACE TEMP VIEW nwr_by_id AS SELECT * FROM nwr_by_geom;

CREATE INDEX IF NOT EXISTS osm_base_idx_id_36 ON osm_base_r((id+3600000000));
CREATE OR REPLACE TEMP VIEW area_by_geom AS
SELECT id + 3600000000 AS id, version, NULL::integer AS changeset, created, tags, NULL::text AS user, NULL::integer AS uid, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'a' AS osm_type FROM osm_base_areas
UNION ALL
SELECT id, version, changeset_id AS changeset, created, tags, NULL::text AS user, uid, NULL::bigint[] AS nodes, NULL::jsonb AS members, ST_MakePolygon(geom)::geometry(Geometry,4326) AS geom, 'w' AS osm_type FROM osm_base_w WHERE ST_NPoints(geom) >= 4 AND ST_IsClosed(geom) AND ST_Dimension(ST_MakePolygon(geom)) = 2
;
CREATE OR REPLACE TEMP VIEW area_by_id AS SELECT * FROM area_by_geom;
