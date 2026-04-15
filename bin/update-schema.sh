#!/bin/bash

set -eu

source $(dirname $0)/_lib.sh

projects_path ${1:-} # Fills variables PROJECTS, PROJECTS_CONFIG_PATH and PROJECTS_DATA_PATH

for PROJECT in $PROJECTS; do
    PROJECT=$(basename "$PROJECT")
    [ ! -d ${PROJECTS_DATA_PATH}/${PROJECT} ] && continue

    echo
    echo $PROJECT
    echo

    read_config $PROJECT # Fills variables EXTRACT_URLS and CHECK_REF_INTEGRITY

    exec {LOCK_FD}> ${PROJECTS_DATA_PATH}/${PROJECT}/lock
    flock $LOCK_FD

    # Check if schema/table exist
    psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT * FROM \"${PROJECT}\".osm_changes LIMIT 1" 2&> /dev/null && {
        # if CHECK_REF_INTEGRITY not empty
        if [ -n "$CHECK_REF_INTEGRITY" ]; then
            psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema="${PROJECT}" -f lib/time_machine/sql/schema/schema-check-integrity.sql
        fi

        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema="${PROJECT}" -f lib/time_machine/sql/schema/schema_changes_geom.sql
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema="${PROJECT}" -f lib/time_machine/sql/schema/schema_geom.sql
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema="${PROJECT}" -f lib/time_machine/sql/changes_logs.sql
    } || echo "Fails to update non initialized project $PROJECT"

    exec {LOCK_FD}>&-
done
