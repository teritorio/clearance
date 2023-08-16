# frozen_string_literal: true
# typed: strict

require 'optparse'
require './time_machine/time_machine'
require './time_machine/validators/validator'
require './time_machine/types'
require './time_machine/configuration'
require './time_machine/db'

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
      ChangesDb.changes_prune(conn)
    }
  end

  if @options[:apply_unclibled_changes]
    osm_tags_matches = T.cast(T.must(config.validators.find{ |v| v.is_a?(Validators::TagsChanges) }), Validators::TagsChanges).osm_tags_matches
    Db::DbConnWrite.conn(project){ |conn|
      ChangesDb.apply_unclibled_changes(conn, osm_tags_matches.to_sql(->(s) { conn.method(s) }))
    }
  end

  if @options[:validate]
    Db::DbConnWrite.conn(project){ |conn|
      TimeMachine.validate(conn, config)
    }
  end

  if @options[:fetch_changesets]
    Db::DbConnWrite.conn(project){ |conn|
      Changeset.get_missing_changeset_ids(conn)
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
