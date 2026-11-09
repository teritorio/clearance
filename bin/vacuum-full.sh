#!/bin/bash

set -eu
set -o pipefail

source "$(dirname "$0")/_lib.sh"

projects_path "${1:-}" # Fills variables PROJECTS, PROJECTS_CONFIG_PATH and PROJECTS_DATA_PATH


TABLES=${TABLES:-"osm_base_n_lat_lon osm_base_w osm_base_r osm_changes osm_changes_applyed"}

exec {LOCK_FD}> "${PROJECTS_DATA_PATH}/lock"
if ! flock --nonblock "$LOCK_FD"; then
    echo "${PROJECTS_DATA_PATH} already locked, abort"
    exit 1
fi

DB_TABLES=$(
    psql "$DATABASE_URL" -v ON_ERROR_STOP=ON -At -F '|' -c "
        SELECT
            '\"' || n.nspname || '\"' || '.' || c.relname AS table_name,
            pg_size_pretty(pg_total_relation_size(c.oid))
        FROM
            pg_class AS c
            JOIN pg_namespace AS n ON
                n.oid = c.relnamespace
        WHERE
            c.relkind = 'r' AND
            c.relname = ANY (string_to_array('$TABLES', ' '))
        ORDER BY
            pg_total_relation_size(c.oid)
    "
)

if [ -z "$DB_TABLES" ]; then
    echo "No target tables found"
else
    while IFS='|' read -r TABLE SIZE; do
        echo "VACUUM FULL ANALYZE ${TABLE} (${SIZE})"
        psql "$DATABASE_URL" -v ON_ERROR_STOP=ON -c "VACUUM FULL ANALYZE ${TABLE}"
    done <<< "$DB_TABLES"
fi

exec {LOCK_FD}>&-
