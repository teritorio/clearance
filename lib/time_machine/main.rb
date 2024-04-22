# frozen_string_literal: true
# typed: strict

require 'sentry'
require 'optparse'
require 'overpass_parser/sql_dialect/postgres'
require './lib/time_machine/validation/time_machine'
require './lib/time_machine/validation/changes_db'
require './lib/time_machine/configuration'
require './lib/time_machine/db/changeset'
require './lib/time_machine/db/db_conn'
require './lib/time_machine/db/export'

if ENV['SENTRY_DSN_TOOLS']
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN_TOOLS']
    # enable performance monitoring
    config.enable_tracing = true
    # get breadcrumbs from logs
    config.breadcrumbs_logger = [:http_logger]
  end
end

@options = T.let({}, T::Hash[Symbol, T.untyped])
OptionParser.new { |opts|
  opts.on('-h', '--help', 'Help') do
    @options[:help] = true
  end
  opts.on('-pPROJECT', '--project=PROJECT', 'Project directory to use.') do |project|
    @options[:project] = project
  end
  opts.on('-p', '--changes-prune', 'Changes prune.') do
    @options[:changes_prune] = true
  end
  opts.on('-u', '--apply-unclibled-changes', 'Apply unclibled changes.') do
    @options[:apply_unclibled_changes] = true
  end
  opts.on('-c', '--fetch_changesets', 'Fetch and store changesets details.') do
    @options[:fetch_changesets] = true
  end
  opts.on('-v', '--validate', 'Ouput list of acceptable changes.') do
    @options[:validate] = true
  end
  opts.on('-e', '--export-osm', 'Export XML OSM dump.') do
    @options[:export_osm] = true
  end
  opts.on('-E', '--export-osm-update', 'Export XML OSM Update.') do
    @options[:export_osm_update] = true
  end
}.parse!

if @options[:help]
  puts 'RTFC'
else
  project = @options[:project].split('/')[-1]
  config = Configuration.load("#{@options[:project]}/config.yaml")

  if @options[:changes_prune]
    Db::DbConnWrite.conn(project) { |conn|
      Validation.changes_prune(conn)
    }
  end

  if @options[:apply_unclibled_changes]
    osm_tags_matches = T.cast(T.must(config.validators.find{ |v| v.is_a?(Validators::TagsChanges) }), Validators::TagsChanges).osm_tags_matches
    polygons = T.let(config.user_groups.values.collect(&:polygon_geojson).compact, T::Array[T::Hash[String, T.untyped]])
    Db::DbConnWrite.conn(project){ |conn|
      dialect = OverpassParser::SqlDialect::Postgres.new(postgres_escape_literal: ->(s) { conn.escape_literal(s) })
      Validation.apply_unclibled_changes(conn, osm_tags_matches.to_sql(dialect), polygons)
    }
  end

  if @options[:validate]
    Db::DbConnWrite.conn(project){ |conn|
      Validation.validate(conn, config)
    }
  end

  if @options[:fetch_changesets]
    Db::DbConnWrite.conn(project){ |conn|
      Db.get_missing_changeset_ids(conn)
    }
  end

  if @options[:export_osm]
    Db::DbConnRead.conn(project){ |conn|
      Db.export(conn, "/projects/#{project}/export/#{project}.osm.bz2")
    }
  elsif @options[:export_osm_update]
    Db::DbConnWrite.conn(project){ |conn|
      Db.export_update(conn, project)
    }
  end
end
