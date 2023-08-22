DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i /scripts/schema.sql
\i /scripts/schema_geom.sql

-- Test osm_base WHERE objtype = 'w' update


-- Test create way
BEGIN;
INSERT INTO osm_base VALUES
  ('n', 1, 1, 1, NULL, NULL, NULL, NULL, 1, 1, NULL, NULL),
  ('n', 2, 1, 1, NULL, NULL, NULL, NULL, 2, 2, NULL, NULL)
;
INSERT INTO osm_base VALUES
  ('w', 3, 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 2], NULL)
;
COMMIT;

do $$ BEGIN
  ASSERT 'LINESTRING(1 1,2 2)' = (SELECT ST_AsText(geom) FROM osm_base WHERE objtype = 'w'),
    (SELECT ST_AsText(geom) FROM osm_base WHERE objtype = 'w');
END; $$ LANGUAGE plpgsql;


-- Test change node location
BEGIN;
UPDATE osm_base SET lon = 3, lat = 3 WHERE objtype = 'n' AND id = 1;
COMMIT;

do $$ BEGIN
  ASSERT 'LINESTRING(3 3,2 2)' = (SELECT ST_AsText(geom) FROM osm_base WHERE objtype = 'w'),
    (SELECT ST_AsText(geom) FROM osm_base WHERE objtype = 'w');
END; $$ LANGUAGE plpgsql;


-- Test change way attribute
BEGIN;
UPDATE osm_base SET version = 2 WHERE objtype = 'w' AND id = 3;
COMMIT;

SELECT objtype, id, nodes, ST_AsText(geom) FROM osm_base;

do $$ BEGIN
  ASSERT 2 = (SELECT version FROM osm_base WHERE objtype = 'w'),
    (SELECT version FROM osm_base WHERE objtype = 'w');
END; $$ LANGUAGE plpgsql;


-- Test change way nodes
BEGIN;
UPDATE osm_base SET nodes = ARRAY[1, 1] WHERE objtype = 'w' AND id = 3;
COMMIT;

SELECT objtype, id, nodes, ST_AsText(geom) FROM osm_base;
SELECT * FROM osm_base_changes_ids;
SELECT * FROM osm_base_changes_flag;

do $$ BEGIN
  ASSERT 'LINESTRING(3 3,3 3)' = (SELECT ST_AsText(geom) FROM osm_base WHERE objtype = 'w'),
    (SELECT ST_AsText(geom) FROM osm_base WHERE objtype = 'w');
END; $$ LANGUAGE plpgsql;


-- Test delete way
BEGIN;
DELETE FROM osm_base WHERE objtype = 'w' AND id = 3;
COMMIT;

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM osm_base WHERE objtype = 'w'),
    (SELECT count(*) FROM osm_base WHERE objtype = 'w');
END; $$ LANGUAGE plpgsql;
