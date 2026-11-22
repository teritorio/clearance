SET search_path TO :"schema", public;


-- Ways


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
        LEFT JOIN osm_base_n_lat_lon AS osm_base_n ON
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


-- Nodes


CREATE TABLE IF NOT EXISTS osm_base_n_deleted_ids(
  id BIGINT PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS osm_base_n_deleted_flag(
  flag BOOLEAN PRIMARY KEY
);

CREATE OR REPLACE FUNCTION osm_base_n_log_delete() RETURNS trigger AS $$
BEGIN
    INSERT INTO osm_base_n_deleted_ids (id)
    SELECT
        id
    FROM
        old_rows
    WHERE true
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO osm_base_n_deleted_flag VALUES (true) ON CONFLICT (flag) DO NOTHING;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION osm_base_n_check_fk() RETURNS trigger AS $$
DECLARE
    n integer;
    r record;
    missing_reference boolean := false;
BEGIN
    DROP TABLE IF EXISTS node_groups;
    CREATE TEMP TABLE IF NOT EXISTS node_groups AS
    WITH
    flagged AS (
        SELECT
            id,
            (id - LAG(id, 1, id) OVER (ORDER BY id) > 10000)::int AS is_break
        FROM
            osm_base_n_deleted_ids
    ),
    batch AS (
        SELECT
            id,
            sum(is_break) OVER (ORDER BY id) AS batch_num
        FROM
            flagged
    ),
    numbered AS (
        SELECT
            id,
            batch_num,
            (row_number() OVER (PARTITION BY batch_num ORDER BY id) - 1) / 10000 AS chunk_num
        FROM
            batch
    )
    SELECT
        array_agg(id ORDER BY id) AS ids
    FROM
        numbered
    GROUP BY
        batch_num, chunk_num
    ORDER BY
        batch_num, chunk_num
    ;

    ANALYZE node_groups;
    RAISE NOTICE 'Checking foreign key constraints for deleted nodes... %', (SELECT count(*) AS count FROM node_groups);

    DROP TABLE IF EXISTS iter;
    CREATE TEMP TABLE iter AS
    SELECT
        osm_base_w.nodes AS osm_base_w_nodes,
        node_groups.ids AS node_groups_ids,
        osm_base_w.id AS way_id
    FROM
        node_groups
        JOIN osm_base_w ON
            osm_base_w.nodes && node_groups.ids
    WITH NO DATA
    ;

    FOR n IN 1..(SELECT count(*) AS count FROM node_groups) LOOP
        TRUNCATE TABLE iter;
        INSERT INTO iter
        SELECT
            osm_base_w.nodes AS osm_base_w_nodes,
            node_groups.ids AS node_groups_ids,
            osm_base_w.id AS way_id
        FROM
            (SELECT * FROM node_groups ORDER BY ids LIMIT 1 OFFSET n - 1) AS node_groups
            JOIN osm_base_w ON
                osm_base_w.nodes && node_groups.ids
        ;

        FOR r IN (
            SELECT
                (SELECT id FROM (SELECT * FROM unnest(osm_base_w_nodes) INTERSECT SELECT unnest(node_groups_ids)) AS t(id) LIMIT 1) id,
                way_id
            FROM
                iter
        ) LOOP
            missing_reference := true;
            RAISE NOTICE 'Node % is still referenced by way %', r.id, r.way_id;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'Checking foreign key constraints for deleted nodes... done.';

    DROP TABLE IF EXISTS node_groups;
    IF missing_reference THEN
        RAISE 'Foreign key constraint violation: some deleted nodes are still referenced by ways.';
    END IF;

    DELETE FROM osm_base_n_deleted_ids;
    DELETE FROM osm_base_n_deleted_flag;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER osm_base_n
  AFTER DELETE
  ON osm_base_n_lat_lon
  REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT
EXECUTE PROCEDURE osm_base_n_log_delete();

DROP TRIGGER IF EXISTS osm_base_n_deleted_flag_trigger ON osm_base_n_deleted_flag;
CREATE CONSTRAINT TRIGGER osm_base_n_deleted_flag_trigger
  AFTER INSERT
  ON osm_base_n_deleted_flag
  INITIALLY DEFERRED
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_n_check_fk();


--
--
-- -- Relations
--
--
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
--         LEFT JOIN osm_base_n_lat_lon AS osm_base_n ON
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
