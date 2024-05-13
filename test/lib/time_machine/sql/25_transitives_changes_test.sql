DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

-- No changes
BEGIN;
INSERT INTO osm_base VALUES
  ('n', 1, 1, 1, NULL, NULL, NULL, NULL, 1, 1, NULL, NULL),
  ('w', 1, 1, 1, NULL, NULL, NULL, NULL, 1, 1, ARRAY[1], NULL)
;
COMMIT;

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM osm_changes),
    (SELECT * FROM osm_changes);
END; $$ LANGUAGE plpgsql;

-- Change node location
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 2, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL)
;
COMMIT;

\i lib/time_machine/sql/25_transitives_changes.sql

do $$ BEGIN
  ASSERT 2 = (SELECT count(*) FROM osm_changes),
    (SELECT * FROM osm_changes);
END; $$ LANGUAGE plpgsql;
