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


Generate OSM tag watch list from remaote data source:
``
docker-compose run --rm api bundle exec rake config:fetch_tag_watches
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
./scripts/setup.sh andorra-poi europe/andorra
```

## Update

Get Update, Import and Generate Validation report in database
```
./scripts/update.sh
```

Run update script from crom:
```
*/1 * * * * cd a-priori-validation-for-osm && bash -c "./scripts/update.sh &>> log-`date --iso`"
```

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
bundle exec srb typecheck --ignore=db,app/models/user.rb,app/controllers/users_controller.rb,app/controllers/users/omniauth_callbacks_controller.rbbundle exec rubocop -c ../.rubocop.yml --autocorrect
bundle exec rake test
```
