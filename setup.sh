#!/bin/bash

set -a

PROJECT=$1
EXTRACT=${2:-europe/france/aquitaine/gironde}

IMPORT=projects/${PROJECT}/import

PBF=${IMPORT}/import.osm.pbf
STATE=${IMPORT}/import.state.txt

mkdir -p ${IMPORT}
wget http://download.openstreetmap.fr/extracts/${EXTRACT}-latest.osm.pbf --no-clobber -O ${PBF}
wget http://download.openstreetmap.fr/extracts/${EXTRACT}.state.txt --no-clobber -O ${STATE}

mkdir -p ${IMPORT}/replication
osmosis --read-replication-interval-init workingDirectory=${IMPORT}/replication
cp ${STATE} ${IMPORT}/replication/state.txt
echo "baseUrl=https://download.openstreetmap.fr/replication/${EXTRACT}/minute/
maxInterval=86400" > ${IMPORT}/replication/configuration.txt


PG_COPY=${IMPORT}/osm_base.pgcopy

docker-compose --env-file .tools.env run --rm ope ope /${PBF} /${IMPORT}/osm_base=o
docker-compose exec -u postgres postgres psql -c "\copy osm_base from '/${PG_COPY}'"
