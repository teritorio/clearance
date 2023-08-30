# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/tags_matches'
require './lib/time_machine/types'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class TagsNonSignificantChangeConfig < Osm::TagsMatch
    sig {
      params(
        match: String,
        values: Osm::TagsMatch,
      ).void
    }
    def initialize(match:, values:)
      super(match)
      @values = values
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[Osm::OsmMatchKey, Osm::TagsMatch]])
    }
    def match(tags)
      return [] unless super(tags)

      @values.match(tags)
    end
  end

  class TagsNonSignificantAdd < Validator
    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        config: T.any(String, T::Array[TagsNonSignificantChangeConfig]),
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, config:, action: nil, action_force: nil, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, action: action, action_force: action_force, description: description)

      @config = T.let(if config.is_a?(Array)
                        config
                      else
                        config_yaml = YAML.unsafe_load_file(config)
                        config_yaml.collect{ |item|
                          TagsNonSignificantChangeConfig.new(
                            match: item['match'],
                            values: Osm::TagsMatch.new(item['values']),
                          )
                        }
                      end, T::Array[TagsNonSignificantChangeConfig])
    end

    sig {
      override.params(
        before: T.nilable(ChangesDb::OSMChangeProperties),
        after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(before, after, diff)
      # If key/values does not exists before, but exists afters, ignore it.
      # If key/values des exists before, but does not exists afters, ignore it.
      @config.each{ |c|
        a = T.let(c.match(after['tags']).collect(&:first), T::Array[String])
        if !before.nil?
          a += c.match(before['tags']).collect(&:first)
        end

        diff.tags.each { |key, action|
          if a.include?(key)
            assign_action(action)
          end
        }
      }
    end
  end
end
