CREATE TEMP TABLE clip AS
SELECT
    ST_MakeValid(ST_Union(ST_GeomFromGeoJSON(geom))) AS geom
FROM
    json_array_elements_text(:polygon::json) AS t(geom)
;
ANALYZE clip;


CREATE TEMP TABLE changes_update AS
WITH
base AS (
    SELECT
        _.*,
        ST_Intersects(clip.geom, _.geom) AS cibled_geom_base
    FROM
        clip,
        osm_base_n AS _
),
changes AS (
    SELECT
        _.*
    FROM
        clip,
        osm_changes_geom AS _
    WHERE
        _.objtype = 'n' AND
        NOT ST_Intersects(clip.geom, _.geom)
)
SELECT
    changes.*
FROM
    changes
    LEFT JOIN base USING (id)
WHERE
    NOT changes.deleted AND
    (
        base.id IS NULL
        OR
        NOT base.cibled_geom_base
    )
;


INSERT INTO changes_update
WITH
base AS (
    SELECT
        _.*,
        ST_Intersects(clip.geom, _.geom) AS cibled_geom_base
    FROM
        clip,
        osm_base_w AS _
),
changes AS (
    SELECT
        _.*
    FROM
        clip,
        osm_changes_geom AS _
    WHERE
        _.objtype = 'w' AND
        NOT ST_Intersects(clip.geom, _.geom)
)
SELECT
    changes.*
FROM
    changes
    LEFT JOIN base USING (id)
WHERE
    NOT changes.deleted AND
    (
        base.id IS NULL
        OR
        (
            NOT base.cibled_geom_base AND
            changes.nodes = base.nodes
        )
    )
;


INSERT INTO changes_update
WITH
base AS (
    SELECT
        _.*,
        ST_Intersects(clip.geom, _.geom) AS cibled_geom_base
    FROM
        clip,
        osm_base_r AS _
),
changes AS (
    SELECT
        _.*
    FROM
        clip,
        osm_changes_geom AS _
    WHERE
        _.objtype = 'r' AND
        NOT ST_Intersects(clip.geom, _.geom)
)
SELECT
    changes.*
FROM
    changes
    LEFT JOIN base USING (id)
WHERE
    NOT changes.deleted AND
    (
        base.id IS NULL
        OR
        (
            NOT base.cibled_geom_base AND
            changes.members = base.members
        )
    )
;
