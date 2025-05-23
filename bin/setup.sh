#!/bin/bash

set -e

PROJECT=$1
CONFIG=projects/${PROJECT}/config.yaml
EXTRACTS=`cat ${CONFIG} | ruby -ryaml -e "puts YAML.load(STDIN).dig('import', 'extracts')&.join(' ')"`
CHECK_REF_INTEGRITY=`cat ${CONFIG} | ruby -ryaml -e "puts YAML.load(STDIN).dig('import', 'check_ref_integrity') == 'true' || ''"`

echo $EXTRACTS

exec {LOCK_FD}> projects/${PROJECT}/lock
if ! flock --nonblock $LOCK_FD; then
    echo "${PROJECT} already locked, abort"
    exit 1
fi

# Clean before re-import
rm -fr projects/${PROJECT}/import/
rm -fr projects/${PROJECT}/export/update
rm -fr projects/${PROJECT}/export/state.txt


for EXTRACT in $EXTRACTS; do
    EXTRACT_STATE=${EXTRACT/.osm.pbf/.state.txt}
    EXTRACT_STATE=${EXTRACT_STATE/-latest/}

    EXTRACT_NAME=$(basename "$EXTRACT")
    IMPORT=projects/${PROJECT}/import/${EXTRACT_NAME/-latest.osm.pbf/}

    PBF=${IMPORT}/import.osm.pbf

    mkdir -p ${IMPORT}
    if [ ! -e "${PBF}" ]; then
        wget ${EXTRACT} --no-clobber -O ${PBF}
    fi

    rm -fr ${IMPORT}/replication
    mkdir -p ${IMPORT}/replication
    osmosis --read-replication-interval-init workingDirectory=${IMPORT}/replication

    SEQUENCE_NUMBER=$(python -c "import osmium; print(osmium.io.Reader('${PBF}', osmium.osm.osm_entity_bits.NOTHING).header().get('osmosis_replication_sequence_number'))")
    TIMESTAMP=$(python -c "import osmium; print(osmium.io.Reader('${PBF}', osmium.osm.osm_entity_bits.NOTHING).header().get('osmosis_replication_timestamp'))")
    echo "sequenceNumber=${SEQUENCE_NUMBER}
    timestamp=${TIMESTAMP}" > ${IMPORT}/replication/state.txt

    BASE_URL=$(python -c "import osmium; print(osmium.io.Reader('${PBF}', osmium.osm.osm_entity_bits.NOTHING).header().get('osmosis_replication_base_url'))")
    echo "baseUrl=${BASE_URL}
    maxInterval=86400" > ${IMPORT}/replication/configuration.txt

    ope /${PBF} =n | gzip > projects/${PROJECT}/import/${EXTRACT_NAME}-n.pgcopy.gz
    ope /${PBF} =w | gzip > projects/${PROJECT}/import/${EXTRACT_NAME}-w.pgcopy.gz
    ope /${PBF} =r | gzip > projects/${PROJECT}/import/${EXTRACT_NAME}-r.pgcopy.gz
done

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "ALTER SYSTEM SET autovacuum = off;" && \
psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT PG_RELOAD_CONF();"

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS ${PROJECT} CASCADE"
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema.sql

zcat projects/${PROJECT}/import/*-n.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT}.osm_base_n FROM stdin" || exit 1 &&
zcat projects/${PROJECT}/import/*-w.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT}.osm_base_w FROM stdin" || exit 1 &&
zcat projects/${PROJECT}/import/*-r.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT}.osm_base_r FROM stdin" || exit 1 &&
rm -f projects/${PROJECT}/import/*.pgcopy.gz

# if CHECK_REF_INTEGRITY not empty
if [ -n "$CHECK_REF_INTEGRITY" ]; then
    psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema-check-integrity.sql
fi
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_changes_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/changes_logs.sql

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "ALTER SYSTEM SET autovacuum = on;" && \
psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT PG_RELOAD_CONF();"

mkdir -p projects/${PROJECT}/export
