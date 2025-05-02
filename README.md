# Clearance backend

"Clearance" is a tool for producing OSM extracts and keeping them up to date while respecting quality rules. It is based on partial and local updates. Rejected data groups must be corrected in OSM or accepted manually. OSM changes to be revised are handled collaboratively by interest groups.

![](https://raw.githubusercontent.com/teritorio/clearance-frontend/master/public/Clearance-process.svg)

Online demo : https://clearance-dev.teritorio.xyz

## Install

Ensure git submodule is ready
```
git submodule init
git submodule update
```

### Build
```
docker compose --profile "*" build
```

### Setup
Copy the configuration file and adapt it.
```
cp .env.template .env
```

Set a private random value for the `SECRET_KEY_BASE` key.

To log into Clearance (to manually validate changes), an OpenStreetMap user is required. Register your Clearance instance as an OAuth 2.0 application on https://www.openstreetmap.org/oauth2/applications.

1. The redirect URL should be `https://[your Clearance backend, could be 127.0.0.1:8000]/users/auth/osm_oauth2/callback`. Only "Read user preferences" permission is required.
2. Fill in the values of `OSM_OAUTH2_ID`, `OSM_OAUTH2_SECRET`, `OSM_OAUTH2_REDIRECT` (your Clearance Frontend, could be `http://127.0.0.1:8000/`) in your `.env` file.

### Start
```
docker compose up -d postgres
```

If required, you can enter into the Postgres shell with:
```
docker compose exec -u postgres postgres psql
```

### Update
After code update, update the database schema:
```
docker compose run --rm api bundle exec rails db:migrate
docker compose run --rm script ./bin/update-schema.sh
```

## Projects

### Configure
Create at least one project inside `projects` from the `projects_template` directory.
Adjust the `config.yaml` and the `export*.osm_tags.json` files.

### Init
Set up the initial OSM extract in the database. Use the project directory name from `projects` and one or more URLs to OSM PBF extracts.
```
docker compose run --rm script ./bin/setup.sh emergency http://download.openstreetmap.fr/extracts/europe/monaco-latest.osm.pbf http://download.openstreetmap.fr/extracts/europe/vatican_city-latest.osm.pbf
```

Note: PBFs from Geofabrik have daily diffs, while OSM-FR have minutely updates.

If you plan to use extract and diff from Clearance, dump the first extract. In all cases, you can use the Overpass-like API.
```
docker compose run --rm script ./bin/dump.sh projects/emergency
```

### Data Update
The update should be done by a cron job but can also be run manually.
Get Update, Import, and Generate Validation report in the database:
```
# All projects
docker compose run --rm script ./bin/update.sh

# Only one project
docker compose run --rm script ./bin/update.sh projects/emergency
```

Run update for all projects from cron every 2 minutes:
```
*/2 * * * * cd clearance && bash -c "docker compose run --rm script ./bin/update.sh &>> log-`date --iso`"
```

Note 1: If you use only Geofabrik, set a daily cron, check the hour of Geofabrik diff release.

Note 2: To lower CPU usage, you can lower the update frequency. It is not required to run it every minute.

### Drop
Drop a project.
```
docker compose run --rm script ./bin/drop.sh emergency
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
bundle exec srb typecheck
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
Engine
  * Ensure database integrity (base and changes, by source type)
  * LoCha splitting strategy on large clusters
  * Support changes on objects larger than a cluster: admin relations, large landuses, rivers

Configuration
  * Add OSM extract URL in the config file to initialize the project from it
  * By feature type
    * LoCha / clustering distance
    * Evaluation of geometry change thresholds

Validators implementation
  * Geometry validity (self-intersections, crossings, unclosed polygons...)
  * Check for broken network continuity
  * Add detection of new duplicate or similar objects
  * Pass-through after retention delay: allow automatic validation of non-disputed features / outside change-in-progress areas
  * Validate again OpenData set
  * Validate changes using external rule sets, like MapCSS from JOSM or Osmose-QA validation

Validation evaluation scoring
  * Fetch user blocks and use them in score
  * Fetch changeset discussions and use them in the score
  * Contributors' reputation: based on external tools / APIs
  * Support equivalent tagging schemas to avoid false positives

UI / UX
  * Partial validation of LoCha
  * RSS by user groups
  * Validation review UI / UX
  * Configuration UI:
    * Display
    * Edit
  * User tools
    * Review status (Fixed, I will do it, Need help...)
    * Data Revert tool
    * Easy creation of changeset discussions or OSM notes
