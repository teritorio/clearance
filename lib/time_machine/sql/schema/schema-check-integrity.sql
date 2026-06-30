SET search_path TO :"schema", public;

CREATE OR REPLACE FUNCTION osm_base_w_check_fk() RETURNS trigger AS $$
DECLARE
    r record;
BEGIN
    SELECT INTO r
        nodes_id,
        new_rows.id AS way_id
    FROM
        new_rows
        JOIN LATERAL unnest(new_rows.nodes) AS t(nodes_id) ON true
        LEFT JOIN osm_base_n ON
            osm_base_n.id = nodes_id
    WHERE
        osm_base_n.id IS NULL
    LIMIT 1
    ;

    IF r.nodes_id IS NOT NULL THEN
        RAISE 'Missing node % from way %', r.nodes_id, r.way_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER osm_base_w
  AFTER INSERT
  ON osm_base_w
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
EXECUTE PROCEDURE osm_base_w_check_fk();

CREATE OR REPLACE TRIGGER osm_base_w_update
  AFTER UPDATE
  ON osm_base_w
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
EXECUTE PROCEDURE osm_base_w_check_fk();

CREATE OR REPLACE FUNCTION osm_base_n_check_fk() RETURNS trigger AS $$
DECLARE
    r record;
BEGIN
    DROP TABLE IF EXISTS node_groups;
    CREATE TEMP TABLE IF NOT EXISTS node_groups AS
    WITH numbered AS (
        SELECT
            id,
            row_number() OVER (ORDER BY id) / 100000 AS batch_num
        FROM
            old_rows
    )
    SELECT
        array_agg(id) AS ids
    FROM
        numbered
    GROUP BY
        batch_num
    ;

    ANALYZE node_groups;
    ANALYZE osm_base_w;

    FOR r IN (
    SELECT
        (SELECT id FROM (SELECT id FROM unnest(osm_base_w.nodes) INTERSECT SELECT unnest(node_groups.ids)) AS t LIMIT 1) id,
        osm_base_w.id AS way_id
    FROM
        node_groups
        JOIN osm_base_w ON
            osm_base_w.nodes && node_groups.ids
    -- LIMIT 1 -- No limit to use index
    ) LOOP
        DROP TABLE IF EXISTS node_groups;
        RAISE 'Node % is still referenced by way %', r.id, r.way_id;
    END LOOP;

    DROP TABLE IF EXISTS node_groups;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER osm_base_n
  AFTER DELETE
  ON osm_base_n
  REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT
EXECUTE PROCEDURE osm_base_n_check_fk();

-- CREATE OR REPLACE FUNCTION osm_base_r_check_fk() RETURNS trigger AS $$
-- DECLARE
--     r record;
-- BEGIN
--     FOR r IN (
--     SELECT
--         relations_members.type,
--         relations_members.ref
--     FROM
--         jsonb_to_recordset(NEW.members) AS relations_members(ref bigint, role text, type text)
--         LEFT JOIN osm_base_n ON
--             relations_members.type = 'n' AND
--             osm_base_n.id = relations_members.ref
--         LEFT JOIN osm_base_w ON
--             relations_members.type = 'w' AND
--             osm_base_w.id = relations_members.ref
--     WHERE
--         osm_base_n.id IS NULL AND
--         osm_base_w.id IS NULL
--     LIMIT 1
--     ) LOOP
--         RAISE 'Missing member % % from relation %', r.type, r.ref, NEW.id;
--     END LOOP;
--     RETURN NULL;
-- END;
-- $$ LANGUAGE plpgsql;

-- CREATE OR REPLACE TRIGGER osm_base_r
--   AFTER INSERT OR UPDATE
--   ON osm_base_r
--   REFERENCING NEW TABLE AS new_rows
--   FOR EACH STATEMENT
-- EXECUTE PROCEDURE osm_base_r_check_fk();
