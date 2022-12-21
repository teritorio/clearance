# frozen_string_literal: true
# typed: strict

require 'optparse'
require './time_machine/watches'
require './time_machine/time_machine'
require './time_machine/validators'
require './time_machine/types'
require './time_machine/config'

@options = T.let({}, T::Hash[Symbol, T.untyped])
OptionParser.new { |opts|
  opts.on('-h', '--help', 'Help') do
    @options[:help] = true
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
}.parse!

if @options[:help]
  puts 'RTFC'
else
  config = Config.load

  if @options[:changes_prune]
    ChangesDb.changes_prune
  end

  if @options[:apply_unclibled_changes]
    osm_filters_tags = Watches.all_osm_filters_tags(config.watches)
    sql = Watches.osm_filters_tags_to_sql(osm_filters_tags)
    ChangesDb.apply_unclibled_changes(sql)
  end

  if @options[:validate]
    config_validators = config.validators
    validators = config_validators ? Validators.validators_factory(config_validators, config.watches) : nil
    TimeMachine.validate(validators || [])
  end
end
