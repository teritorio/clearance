CREATE OR REPLACE TEMP VIEW node AS
SELECT id, version, created, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'n';

CREATE OR REPLACE TEMP VIEW way AS
SELECT id, version, created, tags, nodes, NULL::jsonb AS members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'w';

CREATE OR REPLACE TEMP VIEW relation AS
SELECT id, version, created, tags, NULL::bigint[] AS nodes, members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'r';

CREATE OR REPLACE TEMP VIEW nwr AS
SELECT id, version, created, tags, nodes, members, geom, objtype AS osm_type FROM osm_base;

CREATE OR REPLACE TEMP VIEW area AS
SELECT id + CASE objtype[1] WHEN 'r' THEN 3600000000 ELSE 0 END, version, created, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, CASE objtype[1] WHEN 'w' THEN 'w' ELSE 'a' END AS osm_type FROM osm_base_areas;
