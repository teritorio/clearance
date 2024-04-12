CREATE OR REPLACE TEMP VIEW node AS
SELECT id, version, created, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'n';

CREATE OR REPLACE TEMP VIEW way AS
SELECT id, version, created, tags, nodes, NULL::jsonb AS members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'w';

CREATE OR REPLACE TEMP VIEW relation AS
SELECT id, version, created, tags, NULL::bigint[] AS nodes, members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'r';

CREATE OR REPLACE TEMP VIEW nwr AS
SELECT id, version, created, tags, nodes, members, geom, objtype AS osm_type FROM osm_base;

CREATE OR REPLACE TEMP VIEW area AS
SELECT id + 3600000000 AS id, version, created, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'a' AS osm_type FROM osm_base_areas
UNION ALL
SELECT id, version, created, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'w' AS osm_type FROM osm_base WHERE objtype = 'w' AND ST_Dimension(geom) = 2
;
