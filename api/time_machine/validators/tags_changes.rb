# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/osm_tags_matches'

module Validators
  extend T::Sig

  class Watch < OsmTagsMatchs::OsmTagsMatchSet
    sig {
      params(
        matches: T::Array[OsmTagsMatchs::OsmTagsMatch],
        label: T.nilable(Types::MultilingualString),
        osm_tags_extra: T.nilable(T::Array[String]),
      ).void
    }
    def initialize(matches:, label: nil, osm_tags_extra: nil)
      super(matches)
      @label = label
      @osm_tags_extra = osm_tags_extra
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[String])
    }
    def match(tags)
      main_keys = super(tags)
      main_keys += (@osm_tags_extra&.intersection(tags.keys) || []) if !main_keys.empty?
      main_keys
    end
  end

  class Watches < OsmTagsMatchs::OsmTagsMatchs
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

      w = if watches.is_a?(Watches)
            watches
          else
            Watches.new(YAML.unsafe_load_file(watches).transform_values{ |value|
              Watch.new(
               matches: value['matches']&.collect{ |m| OsmTagsMatchs::OsmTagsMatch.new(m) },
               label: value['label'],
               osm_tags_extra: value['osm_tags_extra'],
             )
            })
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
      match_keys = (
        (before && @watches.match(before['tags']) || []) +
        @watches.match(after['tags'])
      ).intersection(diff.tags.keys)
      match_keys.each{ |key|
        assign_action_reject(T.must(diff.tags[key])) if diff.tags.include?(key)
      }
      (diff.tags.keys - match_keys).each{ |key|
        assign_action_accept(T.must(diff.tags[key])) if diff.tags.include?(key)
      }
    end
  end
end
