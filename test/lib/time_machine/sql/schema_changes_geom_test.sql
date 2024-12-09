DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

-- Test osm_base WHERE objtype = 'w' update

BEGIN;
INSERT INTO osm_base VALUES
  ('n', 1, 1, 1, NULL, NULL, NULL, NULL, 1, 1, NULL, NULL),
  ('n', 2, 1, 1, NULL, NULL, NULL, NULL, 2, 2, NULL, NULL)
;
INSERT INTO osm_base VALUES
  ('w', 3, 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 2], NULL)
;
COMMIT;


-- Test change node location
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL, true)
;
COMMIT;

do $$ BEGIN
  ASSERT 'POINT(3 3)' = (SELECT ST_AsText(geom) FROM osm_changes_geom WHERE objtype = 'n' AND id = 1),
    (SELECT ST_AsText(geom) FROM osm_changes_geom WHERE objtype = 'n' AND id = 1);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;

-- Test change way nodes
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 3, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 1], NULL, true)
;
COMMIT;

do $$ BEGIN
  ASSERT 'LINESTRING(1 1,1 1)' = (SELECT ST_AsText(geom) FROM osm_changes_geom WHERE objtype = 'w'),
    (SELECT ST_AsText(geom) FROM osm_changes_geom WHERE objtype = 'w');
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;

-- Test delete way
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 3, 2, true, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 1], NULL, true)
;
COMMIT;

do $$ BEGIN
  ASSERT true = (SELECT deleted FROM osm_changes_geom WHERE objtype = 'w'),
    (SELECT deleted FROM osm_changes_geom WHERE objtype = 'w');
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;
