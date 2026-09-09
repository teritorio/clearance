# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/changeset_comment'
require './lib/time_machine/validators/changeset_review_requested'
require './lib/time_machine/validators/delayed'
require './lib/time_machine/validators/deleted'
require './lib/time_machine/validators/duplicate'
require './lib/time_machine/validators/geom_changes'
require './lib/time_machine/validators/geom_invalid'
require './lib/time_machine/validators/network'
require './lib/time_machine/validators/tags_changes'
require './lib/time_machine/validators/user_block'
require './lib/time_machine/validators/user_new'
require './lib/time_machine/validators/user_list'
require './lib/time_machine/validators/validator_link'

module Validation
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
      path: String,
      validators_config: T::Hash[String, T::Hash[String, Object]],
      osm_tags_matches: Osm::TagsMatches,
    ).returns(T::Array[Validators::ValidatorBase[Validators::ValidatorBase::ValidatorBaseSettings]])
  }
  def self.validators_factory(path, validators_config, osm_tags_matches)
    validators_config.collect{ |id, config|
      class_name = T.cast(config['instance'], T.nilable(String)) || "Validators::#{camelize(id)}"

      specific_osm_tags = T.cast(config['specific_osm_tags'], T.nilable(String))
      specific_osm_tags_matches = specific_osm_tags.nil? ? nil : Configuration.load_osm_tags(path, { 'specific_osm_tags' => specific_osm_tags })

      config = config.except('instance', 'specific_osm_tags').transform_keys(&:to_sym)

      clazz = Object.const_get(class_name)
      clazz_args = %i[action actions]
      settings = clazz.const_get('Settings').new(
        id: id,
        global_osm_tags_matches: osm_tags_matches,
        specific_osm_tags_matches: specific_osm_tags_matches,
        **config.except(*clazz_args)
      )

      clazz.new(
        settings: settings,
        **config.slice(*clazz_args)
      )
    }
  end
end
