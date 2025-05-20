DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql

-- Test osm_base_w update


-- Test create way
BEGIN;
INSERT INTO osm_base_n VALUES
  (1, 1, 1, NULL, NULL, NULL, NULL, 1, 1),
  (2, 1, 1, NULL, NULL, NULL, NULL, 2, 2)
;
INSERT INTO osm_base_w VALUES
  (3, 1, 1, NULL, NULL, NULL, NULL, ARRAY[1, 2])
;
COMMIT;

do $$ BEGIN
  ASSERT 'LINESTRING(1 1,2 2)' = (SELECT ST_AsText(geom) FROM osm_base_w),
    (SELECT ST_AsText(geom) FROM osm_base_w);
END; $$ LANGUAGE plpgsql;


-- Test change node location
BEGIN;
UPDATE osm_base_n SET lon = 3, lat = 3 WHERE id = 1;
COMMIT;

do $$ BEGIN
  ASSERT 'LINESTRING(3 3,2 2)' = (SELECT ST_AsText(geom) FROM osm_base_w),
    (SELECT ST_AsText(geom) FROM osm_base_w);
END; $$ LANGUAGE plpgsql;


-- Test change way attribute
BEGIN;
UPDATE osm_base_w SET version = 2 WHERE id = 3;
COMMIT;

SELECT id, nodes, ST_AsText(geom) FROM osm_base_w;

do $$ BEGIN
  ASSERT 2 = (SELECT version FROM osm_base_w),
    (SELECT version FROM osm_base_w);
END; $$ LANGUAGE plpgsql;


-- Test change way nodes
BEGIN;
UPDATE osm_base_w SET nodes = ARRAY[1, 1] WHERE id = 3;
COMMIT;

SELECT id, nodes, ST_AsText(geom) FROM osm_base_w;
SELECT * FROM osm_base_changes_ids;
SELECT * FROM osm_base_changes_flag;

do $$ BEGIN
  ASSERT 'LINESTRING(3 3,3 3)' = (SELECT ST_AsText(geom) FROM osm_base_w),
    (SELECT ST_AsText(geom) FROM osm_base_w);
END; $$ LANGUAGE plpgsql;


-- Test delete way
BEGIN;
DELETE FROM osm_base_w WHERE id = 3;
COMMIT;

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM osm_base_w),
    (SELECT count(*) FROM osm_base_w);
END; $$ LANGUAGE plpgsql;
