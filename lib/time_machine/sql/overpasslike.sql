CREATE TEMP VIEW area AS
SELECT id, version, created, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, 'a' AS osm_type FROM osm_base_areas;
CREATE TEMP VIEW node AS
SELECT id, version, created, tags, NULL::bigint[] AS nodes, NULL::jsonb AS members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'n';
CREATE TEMP VIEW way AS
SELECT id, version, created, tags, nodes, NULL::jsonb AS members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'w';
CREATE TEMP VIEW relation AS
SELECT id, version, created, tags, NULL::bigint[] AS nodes, members, geom, objtype AS osm_type FROM osm_base WHERE objtype = 'r';
CREATE TEMP VIEW nwr AS
SELECT id, version, created, tags, nodes, members, geom, objtype AS osm_type FROM osm_base;
