# A Priori Validation for OSM Data

OpenStreetMap copy Synchronization with A Priori Validation.

Keep a copy a OpenStreetMap dat while validating update using rules and manual review when required.

## Build
```
docker-compose --env-file .tools.env build
```

## Configure

Adjust config.yaml

## Start
```
docker-compose up -d postgres
```

Enter postgres with
```
docker-compose exec -u postgres postgres psql
```

## Init
```
wget http://download.openstreetmap.fr/extracts/europe/france/aquitaine/gironde-latest.osm.pbf -P pbf/import
wget http://download.openstreetmap.fr/extracts/europe/france/aquitaine/gironde.state.txt -P pbf/import
```

```
docker-compose --env-file .tools.env run --rm ope ope /pbf/import/gironde-latest.osm.pbf /pbf/import/osm_base=o

docker-compose exec -u postgres postgres psql -c "\copy osm_base from '/pbf/import/osm_base.pgcopy'"
```

```
mkdir -p pbf/import/replication
osmosis --read-replication-interval-init workingDirectory=pbf/import/replication
cp pbf/import/gironde.state.txt pbf/import/replication/state.txt
echo "baseUrl=https://download.openstreetmap.fr/replication/europe/france/aquitaine/gironde/minute/
maxInterval=86400" > pbf/import/replication/configuration.txt
```

## Update
```
osmosis --read-replication-interval workingDirectory=pbf/import/replication --write-xml-change pbf/import/diff.osc.xml.bz2

docker-compose --env-file .tools.env run --rm ope ope -H /pbf/import/diff.osc.xml.bz2 /pbf/import/osm_changes=o

docker-compose exec -u postgres postgres psql -c "\copy osm_changes from '/pbf/import/osm_changes.pgcopy'"

rm -f pbf/import/diff.osc.xml.bz2 pbf/import/osm_changes.pgcopy
```

Validation report
```
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --changes-prune
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --apply_unclibled_changes
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --validate
```

## Export

docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --export-osm /pbf/exports/export.osm.xml
docker-compose --env-file .tools.env run --rm api ruby time_machine/main.rb --export-osm-update /pbf/exports/update/

## Dev

Setup
```
bundle install
bundle exec tapioca init

bundle exec rake rails_rbi:routes
bundle exec tapioca dsl
bundle exec srb rbi suggest-typed
```

Tests and Validation
```
bundle exec srb typecheck
bundle exec rubocop -c ../.rubocop.yml --autocorrect
bundle exec rake test
```
