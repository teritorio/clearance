DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

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


-- Test add no duplicate node
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 100, 100)
;
COMMIT;

\set change_node_ids ARRAY[3]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT (SELECT array_agg(id)::text FROM validator_duplicate) IS NULL,
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test add duplicate node
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 1)
;
COMMIT;

\set change_node_ids ARRAY[3]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{3}' = (SELECT array_agg(id)::text FROM validator_duplicate),
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test add duplicate node at same location
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 0, 1)
;
COMMIT;

\set change_node_ids ARRAY[3]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{3}' = (SELECT array_agg(id)::text FROM validator_duplicate),
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test delete duplicate node
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, true, 1, NULL, NULL, NULL, NULL, 1, 1)
;
COMMIT;

\set change_node_ids ARRAY[3]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT (SELECT array_agg(id)::text FROM validator_duplicate) IS NULL,
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test delete and add duplicate node
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, true, 1, NULL, NULL, NULL, NULL, 1, 1),
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 1)
;
COMMIT;

\set change_node_ids ARRAY[3]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{3}' = (SELECT array_agg(id)::text FROM validator_duplicate),
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test move duplicate node away
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, NULL, 100, 100)
;
COMMIT;

\set change_node_ids ARRAY[1]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT (SELECT array_agg(id)::text FROM validator_duplicate) IS NULL,
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test move duplicate node close
BEGIN;
UPDATE osm_base_n SET lon = 100, lat = 100 WHERE id = 1;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, '{"a":"b"}'::jsonb, 1, 0)
;
COMMIT;

\set change_node_ids ARRAY[1]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{1}' = (SELECT array_agg(id)::text FROM validator_duplicate),
    (SELECT array_agg(id)::text FROM validator_duplicate);
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

\set change_node_ids ARRAY[1]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT '{1}' = (SELECT array_agg(id)::text FROM validator_duplicate),
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
UPDATE osm_base_n SET tags = '{"a":"b"}'::jsonb WHERE id = 1;
TRUNCATE osm_changes;


-- Test add close node with unmatched tag is ignored
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"c"}'::jsonb, 1, 1)
;
COMMIT;

\set change_node_ids ARRAY[3]
\set change_way_ids ARRAY[]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT (SELECT array_agg(id)::text FROM validator_duplicate) IS NULL,
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test add close node with level mismatch is ignored
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 3, 1, false, 1, NULL, NULL, NULL, '{"a":"b","level":"1"}'::jsonb, 1, 1)
;
COMMIT;

\set change_node_ids ARRAY[3]
\set change_way_ids ARRAY[]
\i lib/time_machine/validators/duplicate.sql

do $$ BEGIN
  ASSERT (SELECT array_agg(id)::text FROM validator_duplicate) IS NULL,
    (SELECT array_agg(id)::text FROM validator_duplicate);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;
