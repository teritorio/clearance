#!/bin/bash

set -a

# Get Update
osmosis --read-replication-interval workingDirectory=pbf/import/replication --write-xml-change pbf/import/diff.osc.xml.bz2
# Convert
docker-compose --env-file .tools.env run --rm ope ope -H /pbf/import/diff.osc.xml.bz2 /pbf/import/osm_changes=o
# Import
docker-compose exec -u postgres postgres psql -c "\copy osm_changes from '/pbf/import/osm_changes.pgcopy'"
rm -f pbf/import/diff.osc.xml.bz2 pbf/import/osm_changes.pgcopy

# Validation report
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --changes-prune
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --apply_unclibled_changes
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --validate
