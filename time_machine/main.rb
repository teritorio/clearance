# frozen_string_literal: true
# typed: true

require './time_machine'
require './validators'
require './types'


config_yaml = YAML.unsafe_load_file(T.must(ENV.fetch('CONFIG', nil)))
config = T.let(config_yaml, Types::Config)

config_validators = config.validators
validators = config_validators ? Validators.validators_factory(config_validators) : nil

TimeMachine.time_machine(validators || [])
