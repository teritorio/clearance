# frozen_string_literal: true
# typed: strict

require 'optparse'
require './time_machine/time_machine'
require './time_machine/validators/validator'
require './time_machine/types'
require './time_machine/config'
require './time_machine/db'

@options = T.let({}, T::Hash[Symbol, T.untyped])
OptionParser.new { |opts|
  opts.on('-h', '--help', 'Help') do
    @options[:help] = true
  end
  opts.on('-cCONFIG', '--config=CONFIG', 'YAML Config file to use.') do |config|
    @options[:config] = config
  end
  opts.on('-p', '--changes-prune', 'Changes prune.') do
    @options[:changes_prune] = true
  end
  opts.on('-u', '--apply-unclibled-changes', 'Apply unclibled changes.') do
    @options[:apply_unclibled_changes] = true
  end
  opts.on('-v', '--validate', 'Ouput list of acceptable changes.') do
    @options[:validate] = true
  end
  opts.on('-eDUMP', '--export-osm=DUMP', 'Export XML OSM dump.') do |dump|
    @options[:export_osm] = dump
  end
  opts.on('-cDUMP', '--export-osm-update=DUMP', 'Export XML OSM Update.') do |dump|
    @options[:export_osm_update] = dump
  end
}.parse!

if @options[:help]
  puts 'RTFC'
else
  Dir.chdir(File.dirname(@options[:config]))
  config = Config.load(@options[:config])

  if @options[:changes_prune]
    ChangesDb.changes_prune
  end

  if @options[:apply_unclibled_changes]
    watches = T.cast(T.must(config.validators.find{ |v| v.is_a?(Validators::TagsChanges) }), Validators::TagsChanges).watches
    ChangesDb.apply_unclibled_changes(watches.to_sql)
  end

  if @options[:validate]
    TimeMachine.validate(config.validators)
  end

  if @options[:export_osm]
    Db.export(@options[:export_osm])
  elsif @options[:export_osm_update]
    Db.export_update(@options[:export_osm_update])
  end
end
