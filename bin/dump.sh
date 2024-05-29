#!/bin/bash

set -e

PROJECT=$1
PROJECT_NAME=$(basename "$PROJECT")

mkdir -p ${PROJECT}/export

timestamp=$(cat ${PROJECT}/export/update/state.txt | grep timestamp | cut -d= -f2 | tr -d '\\')
sequenceNumber=$(cat ${PROJECT}/export/update/state.txt | grep sequenceNumber | cut -d= -f2)

bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --export-osm

osmium cat \
    --output-header="osmosis_replication_timestamp=${timestamp}" \
    --output-header="osmosis_replication_sequence_number=${sequenceNumber:-0}" \
    --output-header="osmosis_replication_base_url=${PUBLIC_URL}/api/0.1/${PROJECT_NAME}/extract/update" \
    ${PROJECT}/export/${PROJECT_NAME}.osm.bz2 \
    --overwrite \
    -o ${PROJECT}/export/${PROJECT_NAME}-tmp.osm.pbf &&
mv ${PROJECT}/export/${PROJECT_NAME}-tmp.osm.pbf ${PROJECT}/export/${PROJECT_NAME}.osm.pbf || exit 1 && \
rm -f ${PROJECT}/export/${PROJECT_NAME}.osm.bz2
