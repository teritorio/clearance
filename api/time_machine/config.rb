# frozen_string_literal: true
# typed: true

require 'yaml'

module Config
  extend T::Sig

  def self.load
    config_yaml = YAML.unsafe_load_file(T.must(ENV.fetch('CONFIG', nil)))
    T.let(config_yaml, Types::Config)
  end
end
