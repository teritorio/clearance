# frozen_string_literal: true
# typed: true

require 'optparse'
require 'yaml'
require './watches'
require './time_machine'
require './validators'
require './types'

@options = {}
OptionParser.new { |opts|
  opts.on('-h', '--help', 'Help') do
    @options[:help] = true
  end
  opts.on('-sql', '--sql-filter', 'Output SQL tags filter.') do
    @options[:sql_filter] = true
  end
  opts.on('-auto', '--auto-validate', 'Ouput list of acceptable changes.') do
    @options[:auto_validate] = true
  end
}.parse!

if @options[:help]
  puts 'RTFC'
else
  config_yaml = YAML.unsafe_load_file(T.must(ENV.fetch('CONFIG', nil)))
  config = T.let(config_yaml, Types::Config)

  if @options[:sql_filter]
    osm_filters_tags = Watches.all_osm_filters_tags(config.watches)
    sql = Watches.osm_filters_tags_to_sql(osm_filters_tags)
    puts sql
  elsif @options[:auto_validate]
    config_validators = config.validators
    validators = config_validators ? Validators.validators_factory(config_validators) : nil

    TimeMachine.auto_validate(validators || [])
  end
end
