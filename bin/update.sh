#!/bin/bash

set -e

PROJECTS=${1:-$(find projects/ -maxdepth 1 -type d -not -name projects)}

for PROJECT in $PROJECTS; do
    echo $PROJECT
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
        docker-compose --env-file .tools.env run --rm ope ope -H /${IMPORT}/diff.osc.xml.bz2 /${IMPORT}/osm_changes=o && \
        rm -f ${IMPORT}/diff.osc.xml.bz2
        # Import
        docker-compose exec -T -u postgres postgres psql -v ON_ERROR_STOP=ON -c "\copy ${PROJECT_NAME}.osm_changes from '/${IMPORT}/osm_changes.pgcopy'" && \
        rm -f ${IMPORT}/osm_changes.pgcopy

        # Validation report
        docker-compose --env-file .tools.env run --rm api ruby lib/time_machine/main.rb --project=/${PROJECT} --changes-prune && \
        docker-compose --env-file .tools.env run --rm api ruby lib/time_machine/main.rb --project=/${PROJECT} --apply_unclibled_changes && \
        docker-compose --env-file .tools.env run --rm api ruby lib/time_machine/main.rb --project=/${PROJECT} --fetch_changesets && \
        docker-compose --env-file .tools.env run --rm api ruby lib/time_machine/main.rb --project=/${PROJECT} --validate && \
        docker-compose --env-file .tools.env run --rm api ruby lib/time_machine/main.rb --project=/${PROJECT} --export-osm-update
    else
        echo "${PROJECT} Update already locked"
    fi
done
