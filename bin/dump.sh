#!/bin/bash

set -e

PROJECTS_CONFIG_PATH=${PROJECTS_CONFIG_PATH:-projects_config}
PROJECTS_DATA_PATH=${PROJECTS_DATA_PATH:-projects_data}
PROJECT=$1

mkdir -p ${PROJECTS_DATA_PATH}/${PROJECT}/export

timestamp=$(cat ${PROJECTS_DATA_PATH}/${PROJECT}/export/update/state.txt | grep timestamp | cut -d= -f2 | tr -d '\\')
sequenceNumber=$(cat ${PROJECTS_DATA_PATH}/${PROJECT}/export/update/state.txt | grep sequenceNumber | cut -d= -f2)

bundle exec ruby lib/time_machine/main.rb --project=${PROJECT} --export-osm | \
osmium cat \
    --input-format=xml \
    --output-header="osmosis_replication_timestamp=${timestamp}" \
    --output-header="osmosis_replication_sequence_number=${sequenceNumber:-0}" \
    --output-header="osmosis_replication_base_url=${PUBLIC_URL}/api/0.1/${PROJECT}/export/update/" \
    --overwrite \
    --output=${PROJECTS_DATA_PATH}/${PROJECT}/export/${PROJECT}-tmp.osm.pbf && \
mv ${PROJECTS_DATA_PATH}/${PROJECT}/export/${PROJECT}-tmp.osm.pbf ${PROJECTS_DATA_PATH}/${PROJECT}/export/${PROJECT}.osm.pbf || exit 1
