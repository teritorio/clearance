DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

\set group_id_polys '\'[["pop", { "type": "Polygon", "coordinates": [ [ [ -180 , -90 ], [ -180, 90 ], [ 180, 90 ], [ 180, -90 ], [ -180 , -90 ] ] ] }]]\''

\i lib/time_machine/sql/30_fetch_changes.sql

CREATE TEMP VIEW a AS
SELECT * FROM fetch_changes(:group_id_polys::jsonb);

-- No changes
BEGIN;
INSERT INTO osm_base VALUES
  ('n', 1, 1, 1, NULL, NULL, NULL, NULL, 1, 1, NULL, NULL),
  ('n', 101, 1, 1, NULL, NULL, NULL, NULL, 1, 1, NULL, NULL),
  ('n', 102, 1, 1, NULL, NULL, NULL, NULL, 1, 1, NULL, NULL),
  ('w', 100, 1, 1, NULL, NULL, NULL, NULL, 1, 1, ARRAY[101], NULL)
;
COMMIT;

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM a),
    (SELECT * FROM a);
END; $$ LANGUAGE plpgsql;


-- Change node location
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 2, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL),
  ('n', 1, 3, false, 3, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL),
  ('n', 1, 3, true, 4, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL)
;
COMMIT;

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM a),
    'Changes numbers';
  ASSERT 2 = (SELECT jsonb_array_length(p) FROM a),
    'Objects version';

  -- base
  ASSERT '1' = (SELECT p->0->>'version' FROM a),
    'Version base';
  ASSERT 'false' = (SELECT p->0->>'deleted' FROM a),
    'Deleted base';

  -- change
  ASSERT '3' = (SELECT p->1->>'version' FROM a),
    'Version change';
  ASSERT 'true' = (SELECT p->1->>'deleted' FROM a),
    'Deleted change';
END; $$ LANGUAGE plpgsql;



-- Get all changesets
BEGIN;
INSERT INTO osm_changesets VALUES
  (1, '1999-01-08 04:05:06', NULL, false, 'bob', 1, NULL, NULL, NULL, NULL, 0, 0, '{}'::jsonb),
  (2, '1999-01-08 04:05:06', NULL, false, 'bob', 1, NULL, NULL, NULL, NULL, 0, 0, '{}'::jsonb),
  (3, '1999-01-08 04:05:06', NULL, false, 'bob', 1, NULL, NULL, NULL, NULL, 0, 0, '{}'::jsonb),
  (4, '1999-01-08 04:05:06', NULL, false, 'bob', 1, NULL, NULL, NULL, NULL, 0, 0, '{}'::jsonb)
;
COMMIT;

do $$ BEGIN
  ASSERT 3 = (SELECT jsonb_array_length(p->1->'changesets') FROM a),
    (SELECT jsonb_array_length(p->1->'changesets') FROM a);
END; $$ LANGUAGE plpgsql;



-- Change way nodes
BEGIN;
TRUNCATE osm_changes;
INSERT INTO osm_changes VALUES
  ('w', 100, 2, false, 2, NULL, NULL, NULL, NULL, 1, 1, ARRAY[101, 102], NULL)
;
COMMIT;

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM a),
    'Changes numbers';

  -- base
  ASSERT '1' = (SELECT p->0->>'version' FROM a),
    'Version base';
  ASSERT 'false' = (SELECT p->0->>'deleted' FROM a),
    'Deleted base';

  -- change
  ASSERT '2' = (SELECT p->1->>'version' FROM a),
    'Version change';
  ASSERT 'false' = (SELECT p->1->>'deleted' FROM a),
    'Deleted change';
END; $$ LANGUAGE plpgsql;
