# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/types'
require './time_machine/validators/deleted'
require './time_machine/validators/geom_changes'
require './time_machine/validators/geom_new_object'
require './time_machine/validators/tags_changes'
require './time_machine/validators/user_list'
require './time_machine/validators/validator'

module Validators
  extend T::Sig

  # Adapted from activesupport/lib/active_support/inflector/methods.rb, line 69
  sig { params(term: String).returns(String) }
  def self.camelize(term)
    string = term.to_s
    string = string.sub(/^[a-z\d]*/, &:capitalize)
    string.gsub!(%r{(?:_|(/))([a-z\d]*)}) { "#{Regexp.last_match(1)}#{T.must(Regexp.last_match(2)).capitalize}" }
    string.gsub!('/', '::')
    string
  end

  sig {
    params(
      validators_config: T::Hash[String, T::Hash[String, Object]],
    ).returns(T::Array[ValidatorBase])
  }
  def self.validators_factory(validators_config)
    validators_config.collect{ |id, config|
      class_name = T.cast(config['instance'], T.nilable(String)) || "Validators::#{camelize(id)}"
      args = config.except('instance').transform_keys(&:to_sym)
      Object.const_get(class_name).new(id: id, **args)
    }
  end
end
