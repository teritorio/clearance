# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'yaml'
require './time_machine/validators/validator_factory'

module Config
  extend T::Sig

  class MainConfig < T::Struct
    const :title, T::Hash[String, String]
    const :description, T::Hash[String, String]
    const :validators, T::Hash[String, T::Hash[String, Object]]
    const :user_groups, T::Hash[String, T::Hash[String, Object]]
  end

  class UserGroupConfig < T::Struct
    const :title, T::Hash[String, String]
    const :polygon, T.nilable(String)
    const :users, T::Array[String]
  end

  class Config < T::Struct
    const :title, T::Hash[String, String]
    const :description, T::Hash[String, String]
    const :validators, T::Array[Validators::ValidatorBase]
    const :user_groups, T::Hash[String, UserGroupConfig]
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

    config.user_groups.transform_values{ |v|
      UserGroupConfig.new(v&.transform_keys(&:to_sym) || {})
    }

    Config.new(
      title: config.title,
      description: config.description,
      validators: validators,
      user_groups: config.user_groups.transform_values{ |v| UserGroupConfig.new(v&.transform_keys(&:to_sym) || {}) }
    )
  end
end
