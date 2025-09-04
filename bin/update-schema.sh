#!/bin/bash

set -e

PROJECTS_CONFIG_PATH=${PROJECTS_CONFIG_PATH:-projects_config}
PROJECTS_DATA_PATH=${PROJECTS_DATA_PATH:-projects_data}
PROJECTS=${1:-$(find ${PROJECTS_CONFIG_PATH}/* -maxdepth 0 -type d | sed -e 's#${PROJECTS_CONFIG_PATH}##')}

for PROJECT in $PROJECTS; do
    PROJECT=$(basename "$PROJECT")
    [ ! -d ${PROJECTS_DATA_PATH}/${PROJECT} ] && break

    echo
    echo $PROJECT
    echo

    exec {LOCK_FD}> ${PROJECTS_DATA_PATH}/${PROJECT}/lock
    flock $LOCK_FD

    # Check if schema/table exist
    psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT * FROM ${PROJECT}.osm_changes LIMIT 1" 2&> /dev/null && {
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_changes_geom.sql
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_geom.sql
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/changes_logs.sql
    } || echo "Fails to update non initialized project $PROJECT"

    exec {LOCK_FD}>&-
done
