DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

-- add default to 1 at locha_id to avoid null issues
ALTER TABLE osm_changes ALTER COLUMN locha_id SET DEFAULT 1;

\set proj 4326
\set osm_filter_tags true
\set map_select_index 'CASE WHEN _.tags->>''a'' = ''b'' THEN 1 END'
\set map_select_distance 2
\set change_way_ids ARRAY[]


-- Test osm_base_n update
BEGIN;
INSERT INTO osm_base_n VALUES
  (1, 1, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 0),
  (2, 1, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 0, 1)
;
COMMIT;


-- Test same no duplicate node
BEGIN;
INSERT INTO osm_changes VALUES
  -- no change
  ('n', 1, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 0)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{NULL,NULL}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test add no duplicate node
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 100, 100)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{NULL,NULL}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test add duplicate node
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 1)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{"{3}","{{n1,n2}}"}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test two new duplicate nodes
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 101, 100),
  ('n', 4, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 100, 101)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{"{3,4}","{{n4},{n3}}"}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test add duplicate node at same location
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 0, 1)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{"{3}","{{n1,n2}}"}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test delete duplicate node
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, true, 1, NULL, NULL, NULL, NULL, 1, 1)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{NULL,NULL}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- -- Test delete and add duplicate node
-- BEGIN;
-- INSERT INTO osm_changes VALUES
--   ('n', 1, 2, true, 1, NULL, NULL, NULL, NULL, 1, 1),
--   ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 1)
-- ;
-- COMMIT;

-- \i lib/time_machine/validators/duplicate.sql

-- do $$ BEGIN
--   ASSERT '{3}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
--     (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
-- END; $$ LANGUAGE plpgsql;
-- TRUNCATE osm_changes;


-- Test move duplicate node away
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, NULL, 100, 100)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{NULL,NULL}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test move duplicate node close
BEGIN;
UPDATE osm_base_n SET lon = 100, lat = 100 WHERE id = 1;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 0)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{"{1}","{{n2}}"}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
UPDATE osm_base_n SET lon = 1, lat = 0 WHERE id = 1;
TRUNCATE osm_changes;


-- Test add match tags
BEGIN;
UPDATE osm_base_n SET tags = '{}'::jsonb WHERE id = 1;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 0)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{"{1}","{{n2}}"}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
UPDATE osm_base_n SET tags = '{"a":"b"}'::jsonb WHERE id = 1;
TRUNCATE osm_changes;


-- Test add close node with unmatched tag is ignored
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"c"}'::jsonb, 1, 1)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{NULL,NULL}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test add close node with level mismatch is ignored
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b","level":"1"}'::jsonb, 1, 1)
;
COMMIT;

\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{NULL,NULL}' = (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate),
    (SELECT ARRAY[array_agg(id)::text, array_agg(duplicates)::text] FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;
