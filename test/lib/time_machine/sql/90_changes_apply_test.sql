DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

DROP TABLE IF EXISTS changes_update CASCADE;
CREATE TEMP TABLE changes_update (
  objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
  id BIGINT NOT NULL,
  version INTEGER NOT NULL,
  deleted BOOLEAN NOT NULL
);
\set changes_source changes_source
\i lib/time_machine/sql/40_validated_changes.sql

-- Create object
BEGIN;
TRUNCATE changes_update;
INSERT INTO osm_changes VALUES
  ('n', 1, 1, false, 1, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL)
;
INSERT INTO changes_update VALUES
  ('n', 1, 1, false)
;
COMMIT;

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM changes_source),
    (SELECT count(*) FROM changes_source);
END; $$ LANGUAGE plpgsql;

\i lib/time_machine/sql/90_changes_apply.sql

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM osm_base),
    (SELECT count(*) FROM osm_base);
  ASSERT 1 = (SELECT count(*) FROM osm_changes_applyed),
    (SELECT count(*) FROM osm_changes_applyed);
END; $$ LANGUAGE plpgsql;


-- Update object
BEGIN;
TRUNCATE changes_update;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL, true)
;
INSERT INTO changes_update VALUES
  ('n', 1, 2, false)
;
COMMIT;

\i lib/time_machine/sql/90_changes_apply.sql

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM osm_base),
    (SELECT count(*) FROM osm_base);
  ASSERT 2 = (SELECT version FROM osm_base),
    (SELECT version FROM osm_base);
END; $$ LANGUAGE plpgsql;


-- Delete object
BEGIN;
TRUNCATE changes_update;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, true, 1, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL, true)
;
INSERT INTO changes_update VALUES
  ('n', 1, 2, true)
;
COMMIT;

\i lib/time_machine/sql/90_changes_apply.sql

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM osm_base),
    (SELECT count(*) FROM osm_base);
END; $$ LANGUAGE plpgsql;
