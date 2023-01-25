#!/bin/bash

set -a

PROJECT=$1

IMPORT=projects/${PROJECT}/import
CONFIG=projects/${PROJECT}/conf.yaml

# Get Update
osmosis --read-replication-interval workingDirectory=${IMPORT}/replication --write-xml-change ${IMPORT}/diff.osc.xml.bz2
# Convert
docker-compose --env-file .tools.env run --rm ope ope -H /${IMPORT}/diff.osc.xml.bz2 /${IMPORT}/osm_changes=o
# Import
docker-compose exec -u postgres postgres psql -c "\copy osm_changes from '/${IMPORT}/osm_changes.pgcopy'"
rm -f ${IMPORT}/diff.osc.xml.bz2 ${IMPORT}/osm_changes.pgcopy

# Validation report
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --config=/${CONFIG} --changes-prune
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --config=/${CONFIG} --apply_unclibled_changes
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --config=/${CONFIG} --validate
