DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

\set osm_filter_tags true

-- Test osm_base_w update

BEGIN;
INSERT INTO osm_base_n VALUES
  (1, 1, 1, NULL, NULL, NULL, NULL, 1, 1),
  (2, 1, 1, NULL, NULL, NULL, NULL, 2, 2),
  (3, 1, 1, NULL, NULL, NULL, NULL, 3, 3),
  (4, 1, 1, NULL, NULL, NULL, NULL, 4, 4),
  (5, 1, 1, NULL, NULL, NULL, NULL, 5, 5)
;
INSERT INTO osm_base_w VALUES
  (10, 1, 1, NULL, NULL, NULL, NULL, ARRAY[1, 2]),
  (11, 1, 1, NULL, NULL, NULL, NULL, ARRAY[2, 3]),
  (12, 1, 1, NULL, NULL, NULL, NULL, ARRAY[3, 4]),
  (13, 1, 1, NULL, NULL, NULL, NULL, ARRAY[4, 5])
;
COMMIT;


-- Test no connect change
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 10, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 2], NULL, true)
;
COMMIT;

\set base_ways_ids ARRAY[10]
\set change_ways_ids ARRAY[10]
\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network) IS NULL,
    (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test external disconnect way
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 10, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 1], NULL, true)
;
COMMIT;

\set base_ways_ids ARRAY[10]
\set change_ways_ids ARRAY[10]
\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT '{10}{t}{2}' = (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network),
    (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test external new connected way
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 10, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 2, 3], NULL, true)
;
COMMIT;

\set base_ways_ids ARRAY[10]
\set change_ways_ids ARRAY[10]
\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT '{10}{f}{3}' = (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network),
    (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test internal disconnect way
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 11, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[2, 2], NULL, true),
  ('w', 12, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[4, 4], NULL, true)
;
COMMIT;

\set base_ways_ids ARRAY[11, 12]
\set change_ways_ids ARRAY[11, 12]
\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT '{12}{NULL}{NULL}' = (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network),
    (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test internal deleted way
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 11, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[2, 3], NULL, true),
  ('w', 12, 2, true, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true),
  ('w', 13, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[2, 3], NULL, true)
;
COMMIT;

\set base_ways_ids ARRAY[11, 12, 13]
\set change_ways_ids ARRAY[11, 12, 13]
\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT '{12}{NULL}{NULL}' = (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network),
    (SELECT array_agg(id)::text || array_agg(lost_connection)::text || array_agg(node_id)::text FROM validator_network);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;
