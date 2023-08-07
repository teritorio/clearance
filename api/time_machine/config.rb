# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'yaml'
require './time_machine/validators/validator_factory'

module Config
  extend T::Sig

  class MainConfig < T::Struct
    const :description, T::Hash[String, String]
    const :validators, T::Hash[String, T::Hash[String, Object]]
    const :customers, T::Hash[String, T::Hash[String, Object]]
  end

  class Customer < T::Struct
    const :tag_watches, T.nilable(String)
  end

  class Config < T::Struct
    const :description, T::Hash[String, String]
    const :validators, T::Array[Validators::ValidatorBase]
    const :customers, T::Hash[String, Customer]
  end

  sig {
    params(
      path: String
    ).returns(Config)
  }
  def self.load(path)
    config_yaml = YAML.unsafe_load_file(path)
    config = MainConfig.from_hash(config_yaml)
    validators = Validators::ValidatorFactory.validators_factory(config.validators)

    config.customers.transform_values{ |v|
      Customer.new(v&.transform_keys(&:to_sym) || {})
    }

    Config.new(
      description: config.description,
      validators: validators,
      customers: config.customers.transform_values{ |v| Customer.new(v&.transform_keys(&:to_sym) || {}) }
    )
  end
end
