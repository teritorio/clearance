# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'yaml'
require './time_machine/validators/validator_factory'

module Config
  extend T::Sig

  class MainConfig < T::Struct
    const :validators, T::Hash[String, T::Hash[String, Object]]
    const :customers, Object
  end

  class Config < T::Struct
    const :validators, T::Array[Validators::ValidatorBase]
    const :customers, Object
  end

  sig {
    returns(Config)
  }
  def self.load
    config_yaml = YAML.unsafe_load_file(T.must(ENV.fetch('CONFIG', nil)))
    config = MainConfig.from_hash(config_yaml)
    validators = Validators.validators_factory(config.validators)

    Config.new(
      validators: validators,
      customers: config.customers,
    )
  end
end
