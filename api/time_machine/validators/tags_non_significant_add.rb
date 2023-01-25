# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/osm_tags_matches'
require './time_machine/types'

module Validators
  extend T::Sig

  class TagsNonSignificantChangeConfig < OsmTagsMatchs::OsmTagsMatchSet
    sig {
      params(
        matches: T.nilable(T::Array[OsmTagsMatchs::OsmTagsMatch]),
        values: OsmTagsMatchs::OsmTagsMatch,
      ).void
    }
    def initialize(matches:, values:)
      super(matches)
      @values = values
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[String])
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
        config: T.any(String, T::Array[TagsNonSignificantChangeConfig]),
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, config:, action: nil, action_force: nil, description: nil)
      super(id: id, action: action, action_force: action_force, description: description)

      @config = T.let(if config.is_a?(Array)
                        config
                      else
                        config_yaml = YAML.unsafe_load_file(config)
                        config_yaml.collect{ |item|
                          puts item.inspect
                          TagsNonSignificantChangeConfig.new(
                            matches: item['matches']&.collect{ |m| OsmTagsMatchs::OsmTagsMatch.new(m) },
                            values: OsmTagsMatchs::OsmTagsMatch.new(item['values']),
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
        a = c.match(after['tags'])
        if !before.nil?
          a += c.match(before['tags'])
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
