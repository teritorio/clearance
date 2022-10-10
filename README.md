# A Priori Validation for OSM Data

OpenStreetMap copy Synchronization with A Priori Validation.

Keep a copy a OpenStreetMap dat while validating update using rules and manual review when required.

## Build
```
docker-compose build
```

## Configure

Adjust config.yaml

Then
```
docker-compose run --rm time_machine sh -c "ruby main.rb -sql" > sql/osm_filter_tags.sql
```

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
wget http://download.openstreetmap.fr/extracts/europe/france/aquitaine/gironde-latest.osm.pbf -P pbf
wget http://download.openstreetmap.fr/extracts/europe/france/aquitaine/gironde.state.txt -P pbf
```

```
docker-compose run --rm ope ope /pbf/gironde-latest.osm.pbf /pbf/osm_base=o
docker-compose exec -u postgres postgres bash -c "psql -c \"\\copy osm_base from '/pbf/osm_base.pgcopy'\""
```

```
mkdir -p replication
osmosis --read-replication-interval-init workingDirectory=replication
cp gironde.state.txt replication/state.txt
echo "baseUrl=https://download.openstreetmap.fr/replication/europe/france/aquitaine/gironde/minute/
maxInterval=86400" > replication/configuration.txt
```

## Update
```
osmosis --read-replication-interval workingDirectory=replication  --write-xml-change diff.osc.xml.bz2
docker-compose run --rm ope ope -H /pbf/diff.osc.xml.bz2 /pbf/osm_changes=o
docker-compose exec -u postgres postgres bash -c "psql -c \"\\copy osm_changes from '/pbf/osm_changes.pgcopy'\""
rm -f pbf/diff.osc.xml.bz2 pbf/osm_changes.pgcopy
```

Apply untracked changes
```
docker-compose exec -u postgres postgres bash -c 'psql -v ON_ERROR_STOP=1 -v osm_filter_tags="`cat /sql/osm_filter_tags.sql`" < /sql/update.sql'
```

Validation report
```
docker-compose run --rm time_machine sh -c "ruby main.rb"
```

## Dev

```
bundle install
bundle exec srb typecheck
bundle exec rubocop -c ../.rubocop.yml --autocorrect
```
