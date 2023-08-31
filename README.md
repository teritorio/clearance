# Clearance backend

"Clearance" is a tool for producing OSM extracts and keeping them up to date while respecting quality rules. It is based on partial and local updates. Rejected data groups must be corrected in OSM or accepted manually. OSM changes to be revised are handled collaboratively by interest groups.

![](https://raw.githubusercontent.com/teritorio/clearance-frontend/master/public/Clearance-process.svg)

Online demo : https://clearance-dev.teritorio.xyz

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
./bin/setup.sh monaco-poi http://download.openstreetmap.fr/extracts/europe/monaco.osm.pbf
```

```
docker-compose run --rm api bundle exec rails db:migrate
```

## Update

Get Update, Import and Generate Validation report in database
```
./bin/update.sh
```

Run update script from crom:
```
*/2 * * * * cd clearance && bash -c "./bin/update.sh &>> log-`date --iso`"
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
bundle exec srb typecheck --ignore=app/models/user.rb,app/controllers/users_controller.rb,app/controllers/users/omniauth_callbacks_controller.rb
bundle exec rubocop --parallel -c .rubocop.yml --autocorrect
bundle exec rake test
bundle exec rake test:sql
```
