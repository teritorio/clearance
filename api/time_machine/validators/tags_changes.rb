# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/osm_tags_matches'
require './time_machine/validators/validator'

module Validators
  extend T::Sig

  class Watch < OsmTagsMatches::OsmTagsMatch
    sig { returns(T.nilable(T::Array[String])) }
    attr_accessor :sources

    sig {
      params(
        match: String,
        watch: T.nilable(T::Hash[String, T.nilable(String)]),
        sources: T.nilable(T::Array[String])
      ).void
    }
    def initialize(match:, watch: nil, sources: nil)
      super(match)
      @watch = watch
      @sources = sources
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[String, OsmTagsMatches::OsmTagsMatch]])
    }
    def match(tags)
      main_keys = super(tags)
      main_keys += (@watch&.keys&.intersection(tags.keys) || []).collect{ |key| [key, self] } if !main_keys.empty?
      main_keys
    end
  end

  class Watches < OsmTagsMatches::OsmTagsMatches
  end

  class TagsChanges < ValidatorDual
    sig { returns(Watches) }
    attr_reader :watches

    sig {
      params(
        id: String,
        watches: T.any(String, Watches),
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, accept:, reject:, description: nil)
      super(id: id, accept: accept, reject: reject, description: description)

      w = if watches.is_a?(String)
            Watches.new(JSON.parse(File.read(watches)).collect{ |value|
              Watch.new(
               match: value['select'],
               watch: value['interest'],
               sources: value['sources'],
             )
            })
          else
            watches
          end

      @watches = T.let(w, Watches)
    end

    sig {
      override.params(
        before: T.nilable(ChangesDb::OSMChangeProperties),
        after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(before, after, diff)
      watches = (
        (before && @watches.match(before['tags']) || []) +
        @watches.match(after['tags'])
      ).group_by(&:first).select{ |key, _match|
        diff.tags.key?(key)
      }

      watches.each{ |key, matches|
        assign_action_reject(T.must(diff.tags[key]), options: { 'sources' => matches.collect{ |m| m[-1].sources }.flatten })
      }

      (diff.tags.keys - watches.keys).each{ |key, _matches|
        assign_action_accept(T.must(diff.tags[key]))
      }
    end
  end
end
