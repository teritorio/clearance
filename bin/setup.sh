#!/bin/bash

set -e

PROJECT=$1
shift 1
EXTRACTS=${@:-http://download.openstreetmap.fr/extracts/europe/monaco-latest.osm.pbf}

echo $EXTRACTS

LOCK=projects/${PROJECT}/lock
touch $LOCK
exec 8>$LOCK;

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

    ope /${PBF} =o | gzip > projects/${PROJECT}/import/${EXTRACT_NAME}.pgcopy.gz
done

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS ${PROJECT} CASCADE"
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema.sql

zcat projects/${PROJECT}/import/*.pgcopy.gz | sort -k 1,1 -k 2,2n --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT}.osm_base FROM stdin" || exit 1 &&
rm -f projects/${PROJECT}/import/*.pgcopy.gz

psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_changes_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/changes_logs.sql

mkdir -p projects/${PROJECT}/export
