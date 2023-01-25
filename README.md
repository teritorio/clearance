# A Priori Validation for OSM Data

OpenStreetMap copy Synchronization with A Priori Validation.

Keep a copy a OpenStreetMap dat while validating update using rules and manual review when required.

## Build
```
docker-compose --env-file .tools.env build
```

## Configure

Create at least one project inside `projects` from template directory.
Adjust `config.yaml`

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
./setup andorra-poi europe/andorra
```

## Update

Get Update, Import and Generate Validation report in database
```
./update.sh
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
