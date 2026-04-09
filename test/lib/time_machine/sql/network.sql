DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

-- add default to 1 at locha_id to avoid null issues
ALTER TABLE osm_changes ALTER COLUMN locha_id SET DEFAULT 1;

\set osm_filter_tags true

\i lib/time_machine/validators/network.sql
CREATE OR REPLACE FUNCTION vnv() RETURNS TABLE (
  r text
) AS $$
  SELECT
    array_agg(id)::text ||
    coalesce(array_agg(coalesce(base_neighbors_ways::text, 'NULL'))::text, '{}') ||
    coalesce(array_agg(coalesce(change_neighbors_ways::text, 'NULL'))::text, '{}')
  FROM
    validator_network
  ;
$$ LANGUAGE sql STABLE;

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

\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT (SELECT * FROM vnv()) IS NULL,
    (SELECT * FROM vnv());
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test external disconnect way
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 10, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 1], NULL, true)
;
COMMIT;

\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT '{10}{"{11}"}{"NULL"}' = (SELECT * FROM vnv()),
    (SELECT * FROM vnv());
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test external new connected way
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 10, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[1, 2, 3], NULL, true)
;
COMMIT;

\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT '{10}{"{11}"}{"{11,12}"}' = (SELECT * FROM vnv()),
    (SELECT * FROM vnv());
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Test internal disconnect way
BEGIN;
INSERT INTO osm_changes VALUES
  ('w', 11, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[2, 2], NULL, true),
  ('w', 12, 2, false, 1, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY[4, 4], NULL, true)
;
COMMIT;

\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT '{11,12}{"{10,12}","{11,13}"}{"{10}","{13}"}' = (SELECT * FROM vnv()),
    (SELECT * FROM vnv());
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

\i lib/time_machine/validators/network.sql

do $$ BEGIN
  ASSERT '{11,12,13}{"{10,12}","{11,13}","{12}"}{"{10,13}","NULL","{10,11}"}' = (SELECT * FROM vnv()),
    (SELECT * FROM vnv());
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;
