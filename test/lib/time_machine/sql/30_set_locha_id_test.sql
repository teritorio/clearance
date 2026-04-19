DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

\set proj 4326
\set distance 1


-- Test 1 point
-- A single change node should get a locha_id assigned
INSERT INTO osm_changes VALUES
  ('n', 1, 1, false, 1, NULL, NULL, NULL, NULL, 1, 1, NULL, NULL, true)
;

\i lib/time_machine/sql/30_set_locha_id.sql

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM osm_changes WHERE locha_id IS NOT NULL),
    'Single point should have locha_id set';
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test 2 points close
-- Two nearby change nodes should be clustered together (same locha_id)
INSERT INTO osm_changes VALUES
  ('n', 2, 1, false, 1, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, true),
  ('n', 3, 1, false, 1, NULL, NULL, NULL, NULL, 0.5, 0, NULL, NULL, true)
;

\i lib/time_machine/sql/30_set_locha_id.sql

do $$ BEGIN
  ASSERT 2 = (SELECT count(*) FROM osm_changes WHERE locha_id IS NOT NULL),
    'Both close points should have locha_id set';
  ASSERT 1 = (SELECT count(DISTINCT locha_id) FROM osm_changes WHERE locha_id IS NOT NULL),
    'Close points should share the same locha_id';
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test 2 points faraway
-- Two distant change nodes should be in separate clusters (different locha_id)
INSERT INTO osm_changes VALUES
  ('n', 4, 1, false, 1, NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, true),
  ('n', 5, 1, false, 1, NULL, NULL, NULL, NULL, 1000000, 0, NULL, NULL, true)
;

\i lib/time_machine/sql/30_set_locha_id.sql

do $$ BEGIN
  ASSERT 2 = (SELECT count(*) FROM osm_changes WHERE locha_id IS NOT NULL),
    'Both far points should have locha_id set';
  ASSERT 2 = (SELECT count(DISTINCT locha_id) FROM osm_changes WHERE locha_id IS NOT NULL),
    'Far points should have different locha_id';
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test 1 point and 2 null geom
-- All three should get a locha_id assigned, each in its own cluster
INSERT INTO osm_changes VALUES
  ('n', 6, 1, false, 1, NULL, NULL, NULL, NULL,    5,    5, NULL, NULL, true),
  ('n', 7, 1, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true),
  ('n', 8, 1, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true)
;

\i lib/time_machine/sql/30_set_locha_id.sql

do $$ BEGIN
  ASSERT 3 = (SELECT count(*) FROM osm_changes WHERE locha_id IS NOT NULL),
    'All objects including null geom should have locha_id set';
  ASSERT 3 = (SELECT count(DISTINCT locha_id) FROM osm_changes WHERE locha_id IS NOT NULL),
    'Point and null geom objects should each have a distinct locha_id';
END; $$ LANGUAGE plpgsql;
