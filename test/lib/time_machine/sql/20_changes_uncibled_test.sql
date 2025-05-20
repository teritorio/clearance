DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

\set polygon NULL
\set osm_filter_tags false
\set locha_cluster_distance 0
\set distance 0


-- No changes
BEGIN;
INSERT INTO osm_base_n VALUES
  (1, 1, 1, NULL, NULL, NULL, NULL, 1, 1)
;
COMMIT;

\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;


-- Change node location
BEGIN;
INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL, true)
;
COMMIT;

\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;


-- Test include or exclude
BEGIN;
TRUNCATE osm_base_n;
TRUNCATE osm_changes;

INSERT INTO osm_base_n VALUES
  (1, 1, 1, NULL, NULL, NULL, '{"a": "a"}'::jsonb, 1, 1)
;

INSERT INTO osm_changes VALUES
  ('n', 1, 2, false, 1, NULL, NULL, NULL, '{"b": "b"}'::jsonb, 3, 3, NULL, NULL, true)
;
COMMIT;

-- Base in tags, but changes not
\set osm_filter_tags 'tags?\'a\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;

-- Base not in tags, but change yes
\set osm_filter_tags 'tags?\'b\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;

-- All not in tags
\set osm_filter_tags 'tags?\'z\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;
