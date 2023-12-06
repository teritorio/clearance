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
./bin/setup.sh monaco_poi http://download.openstreetmap.fr/extracts/europe/monaco.osm.pbf
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

## What Clearance do and how it works

### OSM Extracts
Clearance start by download an OSM extract from a remote sources like [OSM-FR](download.openstreetmap.fr/) or [Geofabrik](http://download.geofabrik.de/) and load the objects in a Postgres/PostGIS database in raw format (not as spatial object). Each object is a row in the `osm_base` table whatever the object type is.

This `osm_base` table is `the truth`. The data is considered as qualified and with goal to not deteriorate the quality.

The `osm_base` can be queried with an Overpass-like API.

### OSM Update

Updates are fetched from remote source in loop. Minutely available from OSM-FR, and daily available from Geofarik.

The update are loaded in an `osm_changes` table, in the same raw format.

### Update validation processing

Content of `osm_changes` is processed to determine if the changes can be applied to the `osm_base`:
1. If the changes, in `osm_base` or `osm_changes` it is outside of the area of interested it can be applied (note, object can be moved).
2. If `osm_base` or `osm_change` tags are not targeted by the configured tags combination it as also out of interested, and changes can be applied.
3. Then changes of interest in area of interest are subjects to validation rules. Changes not triggering validator rules are also not hold and applied.

Note: hold objects can also be applied to `osm_base` by manual validation.

While changes are applied to `osm_base` it also produces new OSM update files. So The Clearance project act as a OSM Extract/Update proxy with validated data. The Extracts and the Updates are standards and can be used in any OSM compatible tools.

### Validations

The goal is to retain suspect changes as not complying with criteria quality.
The OSM tags properties, the metadata properties, the geometry and the changeset properties can be used to evaluate the quality.

Currently implemented validators:
- deleted: flag deleted object
- geom: flag object with change distance greater than a threshold
- tags: flag object based on tags key and value
- user: flag object based on contributor name

More advanced validators are planned.

After each update the validation is reevaluated. The validation is done using last version of objects. Changes to validate are computed between `osm_base` and the last version of OSM objects.

If a new update make previously retained object pass the validation, is no more retained to changes are applied to `osm_base`. Fixing the objects in OSM make them pass automatically.

#### Logical changes

Not implemented yet.

The idea is to group objects locally to make validation contextual. It allows to detect, and ignore, eg. delete and recreation of the same object. It will also allow to implement multi object validators, eg. to validate road network continuity.

## Roadmap
LoCha v1
  * Clustering strategy (with spatial buffer as naive implementation)
  * Clustering strategy (mix with topological and buffer, configurable by feature type)
  * LoCha splitting strategy on large cluster
  * Support Large object changes:  admin relation, large landuses, rivers

Validators implementation
  * Changes validation
    * Contributors reputation: based on external tools / API
    * Add new duplicate similar object detections
    * Evaluation of geometry changes: implement a distance based on geometry spatial dimensions and feature types, implement threshold based on feature type
    * Pass trough after retention delay: allow automatic validation on non disputed features / not change in progress area
    * Validate again OpenData set
  * Final state validation
    * Final state validation: not validating changes but targeted state using external rules set like MapCSS JSOM/osmose validation

Validation evaluation
  * OSM object independent validation: support splited, merged, redraw objects, spatial dimension changes (requires LoCha)
  * score: implement a global score rather than just negative / neutral / positive

UI / UX
  * Validator UI
  * RSS
  * Configuration UI
