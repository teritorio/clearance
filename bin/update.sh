#!/bin/bash

set -e

PROJECTS=${1:-$(find projects/ -maxdepth 1 -type d -not -name projects -not -name '.*')}

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
        # Get Updates
        EXTRACTS=$(find ${IMPORT}/ -maxdepth 1 -type d -not -name import -name '*')
        TIMESTAMP=$(date +%s)
        [ ! -f ${IMPORT}/diff.osc.xml.bz2 ] && [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
        for EXTRACT in $EXTRACTS; do
        echo "Extract: $EXTRACT"
            osmosis --read-replication-interval workingDirectory=${EXTRACT}/replication --write-xml-change ${IMPORT}/diff-${PROJECT_NAME}-${TIMESTAMP}.osc.xml.bz2
        done

        # Check all extracts have the same sequenceNumber
        STATES=$(find ${IMPORT} -wholename "*/replication/state.txt")
        echo $STATES | wc -w
        if [ "$(echo $STATES | wc -w)" != "$(echo $EXTRACTS | wc -w)" ]; then
            echo "Missing states files. Abort."
            exit 1
        fi
        COUNT_SEQUENCE_NUMBER=$(echo "$STATES" | grep --no-filename sequenceNumber | sort | uniq | wc -l)
        if [ $COUNT_SEQUENCE_NUMBER -gt 1 ]; then
            echo "Different sequenceNumber from state.txt files. Abort."
            exit 2
        fi

        # Merge Updates
        echo osmosis `find ${IMPORT}/diff-*.osc.xml.bz2 | sed -e 's/^/ --read-xml-change /' | tr -d '\n'` --append-change sourceCount=`find ${IMPORT}/diff-*.osc.xml.bz2 | wc -l` --sort-change --simplify-change --write-xml-change ${IMPORT}/diff.osc.xml.bz2
        [ ! -f ${IMPORT}/diff.osc.xml.bz2 ] && [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
        osmosis `find ${IMPORT}/diff-*.osc.xml.bz2 | sed -e 's/^/ --read-xml-change /' | tr -d '\n'` --append-change sourceCount=`find ${IMPORT}/diff-*.osc.xml.bz2 | wc -l` --sort-change --simplify-change --write-xml-change ${IMPORT}/diff.osc.xml.bz2 || exit 3 && \
        rm -f ${IMPORT}/diff-*.osc.xml.bz2

        # Convert
        [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
        ope -H /${IMPORT}/diff.osc.xml.bz2 /${IMPORT}/osm_changes=o || exit 3 && \
        rm -f ${IMPORT}/diff.osc.xml.bz2

        # Import
        psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "\copy ${PROJECT_NAME}.osm_changes from '/${IMPORT}/osm_changes.pgcopy'" || exit 3 && \
        rm -f ${IMPORT}/osm_changes.pgcopy

        # Validation report
        echo "== changes-prune ==" && \
        bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --changes-prune && \
        echo "== apply_unclibled_changes ==" && \
        bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --apply_unclibled_changes && \
        echo "== fetch_changesets ==" && \
        bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --fetch_changesets && \
        echo "== validate ==" && \
        bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --validate && \
        echo "== export-osm-update ==" && \
        bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --export-osm-update
    else
        echo "${PROJECT} Update already locked"
    fi
done
