#!/bin/bash

set -e

PROJECTS=${1:-$(find projects/ -maxdepth 1 -type d -not -name projects)}

for PROJECT in $PROJECTS; do
    PROJECT=$(basename "$PROJECT")
    echo
    echo $PROJECT
    echo

    exec {LOCK_FD}> ${PROJECT}/lock
    flock $LOCK_FD

    # Check if schema/table exist
    psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT * FROM ${PROJECT}.osm_changes LIMIT 1" 2&> /dev/null && {
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_changes_geom.sql
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_geom.sql
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/changes_logs.sql
    } || echo "Fails to update non initialized project $PROJECT"

    exec {LOCK_FD}>&-
done
