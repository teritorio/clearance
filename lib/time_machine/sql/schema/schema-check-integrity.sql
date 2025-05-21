CREATE OR REPLACE FUNCTION osm_base_w_check_fk() RETURNS trigger AS $$
DECLARE
    r record;
BEGIN
    FOR r IN (
    SELECT
        nodes_id
    FROM
        unnest(NEW.nodes) AS t(nodes_id)
        LEFT JOIN osm_base_n ON
            osm_base_n.id = nodes_id
    WHERE
        osm_base_n.id IS NULL
    LIMIT 1
    ) LOOP
        RAISE 'Missing node % from way %', r.nodes_id, NEW.id;
    END LOOP;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER osm_base_w
  AFTER INSERT OR UPDATE
  ON osm_base_w
  FOR EACH ROW
EXECUTE PROCEDURE osm_base_w_check_fk();

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
--             relations_members.type = 'N' AND
--             osm_base_n.id = relations_members.ref
--         LEFT JOIN osm_base_w ON
--             relations_members.type = 'W' AND
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

-- CREATE TRIGGER osm_base_r
--   AFTER INSERT OR UPDATE
--   ON osm_base_r
--   FOR EACH ROW
-- EXECUTE PROCEDURE osm_base_r_check_fk();
