DROP SCHEMA IF EXISTS test CASCADE;
\set schema test
\i lib/time_machine/sql/schema/schema.sql
\i lib/time_machine/sql/schema/schema_geom.sql
\i lib/time_machine/sql/schema/schema_changes_geom.sql

\set polygon NULL
\set osm_filter_tags false
\set locha_cluster_distance 0
\set proj 4326
\set distance 1


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
  ('n', 1, 2, false, 1, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL, true, NULL, 1)
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
  ('n', 1, 2, false, 1, NULL, NULL, NULL, '{"b": "b"}'::jsonb, 3, 3, NULL, NULL, true, NULL, 1)
;
COMMIT;

-- Base in tags, but changes not
\set osm_filter_tags '_.tags?\'a\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;

-- Base not in tags, but change yes
\set osm_filter_tags '_.tags?\'b\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;

-- All not in tags
\set osm_filter_tags '_.tags?\'z\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 1 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;

-- All in tags
\set osm_filter_tags '_.tags?\'a\' OR _.tags?\'b\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT 0 = (SELECT count(*) FROM changes_update),
    (SELECT count(*) FROM changes_update);
END; $$ LANGUAGE plpgsql;


-- Test transitive changes


TRUNCATE osm_base_n;
TRUNCATE osm_changes;
INSERT INTO osm_base_n VALUES
  (1, 1, 1, NULL, NULL, NULL, '{"a": "a"}'::jsonb, 1, 1),
  (2, 1, 1, NULL, NULL, NULL, '{"b": "b"}'::jsonb, 2, 2),
  (9, 1, 1, NULL, NULL, NULL, '{"z": "z"}'::jsonb, 9, 9)
;
INSERT INTO osm_base_w VALUES
  (100, 1, 1, NULL, NULL, NULL, '{"w": "w"}'::jsonb, ARRAY[1, 2])
;


-- From node change, we should get the way change
INSERT INTO osm_changes VALUES
  -- cibled
  ('n', 1, 2, false, 1, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL, true),
  -- not cibled
  ('n', 9, 2, false, 1, NULL, NULL, NULL, NULL, 9, 9, NULL, NULL, true)
;
\set osm_filter_tags '_.tags?\'a\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT array[9]::bigint[] = (SELECT array_agg(id) FROM changes_update),
    (SELECT array_agg(id) FROM changes_update);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- From ways change, we should get the nodes change
INSERT INTO osm_changes VALUES
  -- cibled
  ('n', 1, 2, false, 1, NULL, NULL, NULL, NULL, 3, 3, NULL, NULL, true, NULL, 1),
  -- included by transity
  ('w', 100, 2, false, 2, NULL, NULL, NULL, NULL, 1, 1, ARRAY[1, 2], NULL, true, NULL, 2),
  -- not cibled
  ('n', 9, 2, false, 1, NULL, NULL, NULL, NULL, 9, 9, NULL, NULL, true, NULL, 3)
;
\set osm_filter_tags '_.tags?\'a\''
\i lib/time_machine/sql/20_changes_uncibled.sql

do $$ BEGIN
  ASSERT array[9]::bigint[] = (SELECT array_agg(id) FROM changes_update),
    (SELECT array_agg(id) FROM changes_update);
END; $$ LANGUAGE plpgsql;
TRUNCATE osm_changes;


-- Remove node from way, and delete node
INSERT INTO osm_changes VALUES
  -- cibled
  ('w', 100, 2, false, 2, NULL, NULL, NULL, NULL, 1, 1, ARRAY[1, 9], NULL, true, NULL, 100),
  ('n', 2, 1, true, 1, NULL, NULL, NULL, NULL, 2, 2, NULL, NULL, true, NULL, 2)
;
\set osm_filter_tags '_.tags?\'w\''
\i lib/time_machine/sql/20_changes_uncibled.sql

select array_agg(id) from changes_update;

do $$ BEGIN
  ASSERT (SELECT array_agg(id) FROM changes_update) IS NULL;
END; $$ LANGUAGE plpgsql;
