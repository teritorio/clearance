#!/bin/bash

set -e

PROJECTS=${1:-$(find projects/ -maxdepth 1 -type d -not -name projects)}

for PROJECT in $PROJECTS; do
    IMPORT=${PROJECT}/import
    CONFIG=${PROJECT}/conf.yaml

    PROJECT_NAME=$(basename "$PROJECT")

    LOCK=${PROJECT}/lock
    exec 8>$LOCK;

    if flock -n -x 8; then
        # Get Update
        osmosis --read-replication-interval workingDirectory=${IMPORT}/replication --write-xml-change ${IMPORT}/diff.osc.xml.bz2
        # Convert
        docker-compose --env-file .tools.env run --rm ope ope -H /${IMPORT}/diff.osc.xml.bz2 /${IMPORT}/osm_changes=o
        # Import
        docker-compose exec -T -u postgres postgres psql -v ON_ERROR_STOP=ON -c "\copy ${PROJECT_NAME}.osm_changes from '/${IMPORT}/osm_changes.pgcopy'"
        rm -f ${IMPORT}/diff.osc.xml.bz2 ${IMPORT}/osm_changes.pgcopy

        # Validation report
        docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --project=/${PROJECT} --changes-prune
        docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --project=/${PROJECT} --apply_unclibled_changes
        docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --project=/${PROJECT} --validate

        # Export diff
        docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --project=/${PROJECT} --export-osm-update
    else
        echo "${PROJECT} Update already locked"
    fi
done
