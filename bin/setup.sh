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

docker-compose up -d postgres && sleep 5
docker-compose exec -u postgres postgres psql -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f /scripts/schema.sql

PG_COPY=${IMPORT}/osm_base.pgcopy
docker-compose --env-file .tools.env run --rm ope ope /${PBF} /${IMPORT}/osm_base=o
docker-compose exec -u postgres postgres psql -v ON_ERROR_STOP=ON -c "\copy ${PROJECT}.osm_base from '/${PG_COPY}'"

docker-compose exec -u postgres postgres psql -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f /scripts/schema_geom.sql
docker-compose exec -u postgres postgres psql -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f /scripts/schema_changes_geom.sql
docker-compose exec -u postgres postgres psql -v ON_ERROR_STOP=ON -v schema=${PROJECT} -f /scripts/function.sql

# # Export dump
# mkdir -p projects/${PROJECT}/export
# docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --project=/projects/${PROJECT} --export-osm

touch projects/${PROJECT}/lock
