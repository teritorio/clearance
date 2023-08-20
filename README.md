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
./scripts/setup.sh andorra-poi europe/andorra
```

```
docker-compose run --rm api bundle exec rails db:migrate
```

## Update

Get Update, Import and Generate Validation report in database
```
./scripts/update.sh
```

Run update script from crom:
```
*/1 * * * * cd clearance && bash -c "./scripts/update.sh &>> log-`date --iso`"
```

## Dev

Setup
```
bundle install
bundle exec tapioca init

bundle exec rake rails_rbi:routes
bundle exec tapioca dsl
bundle exec srb rbi suggest-typed

# Remove invalid RBI, and requirer
rm -fr sorbet/rbi/gems/spoom@*
rm -fr sorbet/rbi/gems/tapioca@*
rm -fr sorbet/rbi/gems/rbi*
```

Tests and Validation
```
bundle exec srb typecheck --ignore=db,app/models/user.rb,app/controllers/users_controller.rb,app/controllers/users/omniauth_callbacks_controller.rb
bundle exec rubocop -c ../.rubocop.yml --autocorrect
bundle exec rake test
```
