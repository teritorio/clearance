#!/bin/bash

set -e

PROJECTS=${1:-$(find projects/ -maxdepth 1 -type d -not -name projects -not -name '.*')}

function project() {
    PROJECT=$1

    echo "# Get Updates"
    EXTRACTS=$(find ${IMPORT}/ -maxdepth 1 -type d -not -name import -name '*')
    TIMESTAMP=$(date +%s)
    [ ! -f ${IMPORT}/diff.osc.xml.gz ] && [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
    for EXTRACT in $EXTRACTS; do
        EXTRACT_NAME=$(basename "$EXTRACT")
        osmosis --read-replication-interval workingDirectory=${EXTRACT}/replication --write-xml-change ${IMPORT}/diff-${EXTRACT_NAME}-${TIMESTAMP}.osc.xml.bz2
    done

    echo "# Check all extracts have the same sequenceNumber"
    STATES=$(find ${IMPORT} -wholename "*/replication/state.txt")
    if [ "$(echo $STATES | wc -w)" != "$(echo $EXTRACTS | wc -w)" ]; then
        echo "Missing states files. Abort."
        return 1
    fi
    COUNT_SEQUENCE_NUMBER=$(echo "$STATES" | grep --no-filename sequenceNumber | sort | uniq | wc -l)
    if [ $COUNT_SEQUENCE_NUMBER -gt 1 ]; then
        echo "Different sequenceNumber from state.txt files. Abort."
        return 2
    fi
    cp "$(echo ${STATES} | cut -d ' ' -f1)" ${IMPORT}/state.txt

    echo "# Merge Updates"
    [ -n "$(find ${IMPORT} -name diff-*.osc.xml.bz2 -print -quit)" ] && \
    [ ! -f ${IMPORT}/diff.osc.xml.gz ] && [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
    osmium merge-changes --simplify -o ${IMPORT}/diff.osc.xml.gz $(find ${IMPORT}/diff-*.osc.xml.bz2) || $(rm -f ${IMPORT}/diff.osc.xml.gz && return 3)
    rm -f ${IMPORT}/diff-*.osc.xml.bz2

    echo "# Convert"
    [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
    ope -H /${IMPORT}/diff.osc.xml.gz /${IMPORT}/osm_changes=o || $(rm -f /${IMPORT}/osm_changes.pgcopy && return 4)
    rm -f ${IMPORT}/diff.osc.xml.gz

    echo "# Import"
    echo "== import-changes ==" && \
    bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --import-changes="/${IMPORT}/osm_changes.pgcopy" && \
    rm -f ${IMPORT}/osm_changes.pgcopy

    echo "# Validation report"
    echo "== changes-prune ==" && \
    bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --changes-prune && \
    echo "== apply_unclibled_changes ==" && \
    bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --apply_unclibled_changes && \
    echo "== fetch_changesets ==" && \
    bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --fetch_changesets && \
    echo "== validate ==" && \
    bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --validate && \
    echo "== export-osm-update ==" && \
    bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --export-osm-update && \
    cp ${IMPORT}/state.txt /${PROJECT}/export/state.txt
}

exec {G_LOCK_FD}> projects/lock
if flock --nonblock $G_LOCK_FD; then

    for PROJECT in $PROJECTS; do
        echo
        echo $PROJECT
        echo
        IMPORT=${PROJECT}/import
        CONFIG=${PROJECT}/conf.yaml

        PROJECT_NAME=$(basename "$PROJECT")

        exec {LOCK_FD}> ${PROJECT}/lock
        if flock --nonblock $LOCK_FD; then
            project ${PROJECT} || echo "${PROJECT} Update failed ($?)"
        else
            echo "${PROJECT} already locked, skip"
        fi
        exec {LOCK_FD}>&-
    done

else
    echo "an update is already in progress"
fi
exec {G_LOCK_FD}>&-
