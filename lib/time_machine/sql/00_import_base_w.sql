CREATE TEMP TABLE osm_import (
    id BIGINT NOT NULL,
    version INTEGER NOT NULL,
    changeset_id INTEGER NOT NULL,
    created TIMESTAMP (0) WITHOUT TIME ZONE,
    uid INTEGER,
    username VARCHAR(255),
    tags JSONB,
    nodes BIGINT[]
);
\copy osm_import FROM pstdin;

INSERT INTO :osm_base
SELECT
    id,
    version,
    changeset_id,
    created,
    uid,
    nullif(tags, '{}'::jsonb) AS tags,
    nodes
FROM
    osm_import
;
