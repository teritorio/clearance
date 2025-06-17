#!/bin/bash

set -e

source $(dirname $0)/_lib.sh

PROJECT=$1
PROJECT_NAME=$(basename "$PROJECT")
CONFIG=${PROJECT}/config.yaml
EXTRACTS=`cat ${CONFIG} | ruby -ryaml -e "puts YAML.load(STDIN).dig('import', 'extracts')&.join(' ')"`
CHECK_REF_INTEGRITY=`cat ${CONFIG} | ruby -ryaml -e "puts YAML.load(STDIN).dig('import', 'check_ref_integrity') == 'true' || ''"`

echo $EXTRACTS

exec {LOCK_FD}> ${PROJECT}/lock
if ! flock --nonblock $LOCK_FD; then
    echo "${PROJECT} already locked, abort"
    exit 1
fi

# Clean before re-import
rm -fr ${PROJECT}/import/
rm -fr ${PROJECT}/export/update
rm -fr ${PROJECT}/export/state.txt


for EXTRACT in $EXTRACTS; do
    EXTRACT_NAME=$(basename "$EXTRACT")
    EXTRACT_NAME=${EXTRACT_NAME/-internal/}
    IMPORT=${PROJECT}/import/${EXTRACT_NAME/-latest.osm.pbf/}

    PBF=${IMPORT}/import.osm.pbf

    mkdir -p ${IMPORT}
    if [ ! -e "${PBF}" ]; then
        geofabrik_cookie ${EXTRACT} # Fills variables WGET_OPS and PYOSMIUM_OPS

        wget ${WGET_OPS} ${EXTRACT} --no-clobber -O ${PBF} || (echo "Fails download $EXTRACT, abort" && exit 1)
    fi

    rm -fr ${IMPORT}/replication
    mkdir -p ${IMPORT}/replication
    pyosmium-get-changes ${PYOSMIUM_OPS} \
        --start-osm-data ${PBF} \
        --sequence-file ${IMPORT}/replication/sequence.txt \
        -v \
    2>&1 | grep http | sed -e "s/.*\(http.*\)/\1/" \
    > ${IMPORT}/replication/sequence.url || (echo "pyosmium-get-changes failed"; exit 1)

    SEQUENCE_NUMBER=$(cat ${IMPORT}/replication/sequence.txt)
    TIMESTAMP=$(python -c "import osmium; print(osmium.io.Reader('${PBF}', osmium.osm.osm_entity_bits.NOTHING).header().get('osmosis_replication_timestamp'))")
    echo "sequenceNumber=${SEQUENCE_NUMBER}
timestamp=${TIMESTAMP}" > ${IMPORT}/replication/state.txt

    ope /${PBF} =n | gzip > ${PROJECT}/import/${EXTRACT_NAME}-n.pgcopy.gz
    ope /${PBF} =w | gzip > ${PROJECT}/import/${EXTRACT_NAME}-w.pgcopy.gz
    ope /${PBF} =r | gzip > ${PROJECT}/import/${EXTRACT_NAME}-r.pgcopy.gz
done


echo "# Check all extracts have the same sequenceNumber"
STATES=$(find ${PROJECT}/import/ -wholename "*/replication/state.txt")
if [ "$(echo $STATES | wc -w)" != "$(echo $EXTRACTS | wc -w)" ]; then
    echo "Missing states files. Abort."
    return 1
fi
COUNT_SEQUENCE_NUMBER=$(echo "$STATES" | grep --no-filename sequenceNumber | sort | uniq | wc -l)
if [ $COUNT_SEQUENCE_NUMBER -gt 1 ]; then
    echo "Different sequenceNumber from sequence.txt files. Abort."
    return 2
fi
cp "$(echo ${STATES} | cut -d ' ' -f1)" ${IMPORT}/state.txt

mkdir -p ${PROJECT}/export/update

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "ALTER SYSTEM SET autovacuum = off;" && \
psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT PG_RELOAD_CONF();"

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS ${PROJECT_NAME} CASCADE"
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/schema/schema.sql

zcat ${PROJECT}/import/*-n.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT_NAME}.osm_base_n FROM stdin" || exit 1 &&
zcat ${PROJECT}/import/*-w.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT_NAME}.osm_base_w FROM stdin" || exit 1 &&
zcat ${PROJECT}/import/*-r.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT_NAME}.osm_base_r FROM stdin" || exit 1 &&
rm -f ${PROJECT}/import/*.pgcopy.gz

# if CHECK_REF_INTEGRITY not empty
if [ -n "$CHECK_REF_INTEGRITY" ]; then
    psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/schema/schema-check-integrity.sql
fi
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/schema/schema_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/schema/schema_changes_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/changes_logs.sql

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "ALTER SYSTEM SET autovacuum = on;" && \
psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT PG_RELOAD_CONF();"

mkdir -p ${PROJECT}/export
