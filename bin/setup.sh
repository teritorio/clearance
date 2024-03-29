#!/bin/bash

set -e

PROJECT=$1
EXTRACT=${2:-http://download.openstreetmap.fr/extracts/europe/monaco.osm.pbf}

echo $EXTRACT
EXTRACT_STATE=${EXTRACT/.osm.pbf/.state.txt}
EXTRACT_STATE=${EXTRACT_STATE/-latest/}

IMPORT=projects/${PROJECT}/import

PBF=${IMPORT}/import.osm.pbf

mkdir -p ${IMPORT}
if [ ! -e "${PBF}" ]; then
    wget ${EXTRACT} --no-clobber -O ${PBF}
fi

LOCK=projects/${PROJECT}/lock
touch $LOCK
exec 8>$LOCK;

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

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS ${PROJECT} CASCADE"
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema.sql

ope /${PBF} =o | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT}.osm_base FROM stdin"

psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/schema/schema_changes_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f lib/time_machine/sql/changes_logs.sql

# # Export dump
# mkdir -p projects/${PROJECT}/export
# ruby time_machine/main.rb --project=/projects/${PROJECT} --export-osm
