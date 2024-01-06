#!/bin/bash

set -e

PROJECTS=${1:-$(find projects/ -maxdepth 1 -type d -not -name projects)}

for PROJECT in $PROJECTS; do
    PROJECT=$(basename "$PROJECT")
    echo
    echo $PROJECT
    echo

    psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_changes_geom.sql
    psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/changes_logs.sql
done
