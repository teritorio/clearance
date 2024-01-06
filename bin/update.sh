#!/bin/bash

set -e

PROJECTS=${1:-$(find projects/ -maxdepth 1 -type d -not -name projects)}

for PROJECT in $PROJECTS; do
    echo
    echo $PROJECT
    echo
    IMPORT=${PROJECT}/import
    CONFIG=${PROJECT}/conf.yaml

    PROJECT_NAME=$(basename "$PROJECT")

    LOCK=${PROJECT}/lock
    exec 8>$LOCK;

    if flock -n -x 8; then
        # Get Update
        [ ! -f ${IMPORT}/diff.osc.xml.bz2 ] && [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
        osmosis --read-replication-interval workingDirectory=${IMPORT}/replication --write-xml-change ${IMPORT}/diff.osc.xml.bz2
        # Convert
        [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
        ope -H /${IMPORT}/diff.osc.xml.bz2 /${IMPORT}/osm_changes=o && \
        rm -f ${IMPORT}/diff.osc.xml.bz2
        # Import
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "\copy ${PROJECT_NAME}.osm_changes from '/${IMPORT}/osm_changes.pgcopy'" && \
        rm -f ${IMPORT}/osm_changes.pgcopy

        # Validation report
        echo "== changes-prune ==" && \
        ruby lib/time_machine/main.rb --project=/${PROJECT} --changes-prune && \
        echo "== apply_unclibled_changes ==" && \
        ruby lib/time_machine/main.rb --project=/${PROJECT} --apply_unclibled_changes && \
        echo "== fetch_changesets ==" && \
        ruby lib/time_machine/main.rb --project=/${PROJECT} --fetch_changesets && \
        echo "== validate ==" && \
        ruby lib/time_machine/main.rb --project=/${PROJECT} --validate && \
        echo "== export-osm-update ==" && \
        ruby lib/time_machine/main.rb --project=/${PROJECT} --export-osm-update
    else
        echo "${PROJECT} Update already locked"
    fi
done
