# Clearance backend

"Clearance" is a tool for producing OSM extracts and keeping them up to date while respecting quality rules. It is based on partial and local updates. Rejected data groups must be corrected in OSM or accepted manually. OSM changes to be revised are handled collaboratively by interest groups.

![](https://raw.githubusercontent.com/teritorio/clearance-frontend/master/public/Clearance-process.svg)

Online demo : https://clearance-dev.teritorio.xyz

## Build
```
docker compose --profile "*" build
```

## Configure

Create at least one project inside `projects` from template directory.
Adjust `config.yaml`

## Start
```
docker compose up -d postgres
```

Enter postgres with
```
docker compose exec -u postgres postgres psql
```

## Init

```
docker compose run --rm script ./bin/setup.sh monaco_poi http://download.openstreetmap.fr/extracts/europe/monaco.osm.pbf
```

```
docker compose run --rm api bundle exec rails db:migrate
```

After code update, update the database schema:
```
docker compose run --rm script ./bin/update-schema.sh
```

## Update

Get Update, Import and Generate Validation report in database
```
docker compose run --rm script ./bin/update.sh projects/monaco_poi
```

Run update script from cron:
```
*/2 * * * * cd clearance && bash -c "docker compose run --rm script ./bin/update.sh &>> log-`date --iso`"
```

## Dev

Setup
```
bundle install
bundle exec tapioca init

bundle exec rake rails_rbi:routes
# bundle exec tapioca dsl
bundle exec srb rbi suggest-typed
```

Tests and Validation
```
bundle exec srb typecheck --ignore=app/controllers/users/omniauth_callbacks_controller.rb,sorbet/rbi/annotations/activejob.rbi
bundle exec rubocop --parallel -c .rubocop.yml --autocorrect
docker compose run --rm script bundle exec rake test
docker compose run --rm script bundle exec rake test:sql
```

## What Clearance Does and How It Works

### OSM Extracts
Clearance starts by downloading an OSM extract from remote sources like [OSM-FR](https://download.openstreetmap.fr/) or [Geofabrik](https://download.geofabrik.de/) and loads the objects into a Postgres/PostGIS database in raw format (not as spatial objects). Each object is a row in the `osm_base` table, regardless of the object type.

This `osm_base` table is _the truth_. The data is considered as qualified and with the goal to not deteriorate its quality.

The `osm_base` can be queried with an Overpass API and is also available as an OSM extract with _diff_ updates.

### OSM Incoming Update

Updates are fetched from remote sources in a loop. Minutely updates are available from OSM-FR, and daily updates are available from Geofabrik.

The updates are loaded into an `osm_changes` table, as is, in raw format, without applying the updates.

### Update Validation Processing

The content of `osm_changes` is processed to determine if the changes can be applied to the `osm_base`:
1. If the changes are outside of the area of interest, they can be applied (note: objects can be moved in or out of the area of interest).
2. If the changed tags are not targeted by the configured tag combination, they are also out of interest, then changes can be applied.
3. Changes of interest in the area of interest are subject to validation rules. Changes not triggering any validator rules are also applied to the `osm_base`.

Changes can also be applied to `osm_base` by manual validation, see below.

Held objects are kept in the `osm_changes` table.

While changes are applied to `osm_base`, they are removed from `osm_changes`. Validated changes are available from the Overpass API and as update diffs.

So, the Clearance project acts as an OSM Extract/Update proxy of valid data. The OSM Extracts and Updates are standards and can be used with any OSM compatible tools.

### Validations

The goal is to retain suspect changes as not complying with quality criteria.
The OSM tags properties, the metadata properties, the geometry and the changeset properties can be used to evaluate the quality.

Currently implemented validators:
- deleted: flag deleted objects
- geom: flag objects with change distance greater than a threshold
- tags: flag objects based on tags key and value
- user: flag objects based on contributor name

More advanced validators are planned.

After each update, the validation is reevaluated. The validation is done using the last version of incoming changed objects. Changes to validate are computed between `osm_base` and the last version of OSM objects.

If a new update makes previously retained objects pass the validation, there are no more objects to retain and cumulated changes are applied to `osm_base`.

### Manual Intervention

Held objects rejected by validation must be fixed in order to comply with quality rules. Once fixed in OpenStreetMap, the next update makes them pass the validation and they are available in `osm_base`.

The original OpenStreetMap data is the only modifiable version. All contributions must be done to the original OpenStreetMap database.

In case the change is considered valid according to the user despite the quality rule rejecting it, the integration into the `osm_base` can be accepted manually.

Held objects and manual object acceptance are available via API and user [frontend](https://github.com/teritorio/clearance-frontend/).

#### Logical Changes (LoCha)

The idea is to group changes locally to make contextual validation. It allows detecting, and ignoring, e.g. deletion and recreation of the same object. It also allows implementing multi-object validators, e.g. to validate road network continuity.

## Roadmap
LoCha v1
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
    * Geometry validity (self, crossing, not closed polygon...)
    * Final state validation: not validating changes but targeted state using external rules set like MapCSS JSOM/osmose validation

Validation evaluation
  * OSM object independent validation: support splited, merged, redraw objects, spatial dimension changes (requires LoCha)
  * score: implement a global score rather than just negative / neutral / positive

UI / UX
  * Validator UI
  * RSS
  * Configuration UI
  * User tools
    * Review status (Fixed, I will do it, Need help...)
    * Data Revert tool
