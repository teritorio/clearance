#!/bin/bash

set -e

PROJECTS=${1:-$(find projects/ -maxdepth 1 -type d -not -name projects -not -name '.*')}

function project() {
    PROJECT=$1
    IMPORT=${PROJECT}/import

    echo "# Get Updates"
    EXTRACTS=$(find ${IMPORT}/ -maxdepth 1 -type d -not -name import -name '*')
    if [ -z "$EXTRACTS" ]; then
        echo "No extracts, skip update"
        return 5
    fi
    TIMESTAMP=$(date +%s)
    [ ! -f ${IMPORT}/diff.osc.xml.gz ] && [ ! -f ${IMPORT}/osm_changes.pgcopy ] && \
    for EXTRACT in $EXTRACTS; do
        EXTRACT_NAME=$(basename "$EXTRACT")
        pyosmium-get-changes \
            -v \
            --server $(cat ${EXTRACT}/replication/sequence.url) \
            --sequence-file ${EXTRACT}/replication/sequence.txt \
            --no-deduplicate \
            --outfile ${IMPORT}/diff-${EXTRACT_NAME}-${TIMESTAMP}.osc.xml.bz2
        ret_code=$?

        if [ $ret_code -eq 3 ]; then
            echo "No available OSM update for ${EXTRACT_NAME}"
            continue
        fi

        if [ $ret_code -ne 0 ]; then
            echo "pyosmium-get-changes failed for ${EXTRACT_NAME}"
            return 5
        fi

        SEQUENCE_NUMBER=$(cat ${IMPORT}/replication/sequence.txt)
        TIMESTAMP=
        echo "sequenceNumber=${SEQUENCE_NUMBER}
timestamp=${TIMESTAMP}" > ${IMPORT}/replication/state.txt
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
    if [[ ! -n "$(find ${IMPORT} -name diff-*.osc.xml.bz2 -print -quit)" ]]; then
       echo "no diff-*.osc.xml.bz2, skip merge"
    else
        if [[ -f ${IMPORT}/diff.osc.xml.gz ]]; then
            echo "diff.osc.xml.gz already exist, skip merge"
        else
            if [[ -f ${IMPORT}/osm_changes.pgcopy ]]; then
                echo "osm_changes.pgcopy already exist, skip merge"
            else
                osmium merge-changes --simplify -o ${IMPORT}/diff.osc.xml.gz $(find ${IMPORT}/diff-*.osc.xml.bz2) || (echo "osmium merge-changes fails, clening and abort..." && rm -f ${IMPORT}/diff.osc.xml.gz && return 3)
                rm -f ${IMPORT}/diff-*.osc.xml.bz2
            fi
        fi
    fi

    echo "# Convert"
    if [[ -f ${IMPORT}/osm_changes.pgcopy ]]; then
        echo "osm_changes.pgcopy already exist, skip convert"
    else
        if [[ ! -f ${IMPORT}/diff.osc.xml.gz ]]; then
            echo "no diff.osc.xml.gz, skip convert"
        else
            ope -H /${IMPORT}/diff.osc.xml.gz /${IMPORT}/osm_changes=o || (echo "ope fails, cleaning and abort..." && rm -f /${IMPORT}/osm_changes.pgcopy && return 4)
            rm -f ${IMPORT}/diff.osc.xml.gz
        fi
    fi

    echo "# Import"
    echo "== import-changes ==" && \
    if [[ ! -f ${IMPORT}/osm_changes.pgcopy ]]; then
        echo "no osm_changes.pgcopy, skip import"
    else
        bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --import-changes="/${IMPORT}/osm_changes.pgcopy" && \
        rm -f ${IMPORT}/osm_changes.pgcopy
    fi

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
