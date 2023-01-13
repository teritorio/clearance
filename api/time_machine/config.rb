# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'yaml'
require './time_machine/types'
require './time_machine/validators'

module Config
  extend T::Sig

  class MainConfig < T::Struct
    const :watches, String
    const :validators, T::Hash[String, T::Hash[String, Object]]
    const :customers, Object
  end

  class Config < T::Struct
    const :watches, T::Hash[String, Types::Watch]
    const :validators, T::Array[Validators::ValidatorBase]
    const :customers, Object
  end

  sig {
    returns(Config)
  }
  def self.load
    config_yaml = YAML.unsafe_load_file(T.must(ENV.fetch('CONFIG', nil)))
    config = MainConfig.from_hash(config_yaml)

    watches = YAML.unsafe_load_file(config.watches).transform_values{ |value|
      Types::Watch.from_hash(value)
    }
    validators = Validators.validators_factory(config.validators, watches)

    Config.new(
      watches: watches,
      validators: validators,
      customers: config.customers,
    )
  end
end
