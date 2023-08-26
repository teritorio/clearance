# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm_tags_matches'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class TagsChanges < ValidatorDual
    sig { returns(OsmTagsMatches::OsmTagsMatches) }
    attr_reader :osm_tags_matches

    sig {
      params(
        id: String,
        osm_tags_matches: OsmTagsMatches::OsmTagsMatches,
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, accept:, reject:, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, accept: accept, reject: reject, description: description)
    end

    sig {
      override.params(
        before: T.nilable(ChangesDb::OSMChangeProperties),
        after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(before, after, diff)
      matcheses = (
        (before && @osm_tags_matches.match_with_extra(before['tags']) || []) +
        @osm_tags_matches.match_with_extra(after['tags'])
      ).group_by(&:first).select{ |key, _match|
        diff.tags.key?(key)
      }

      matcheses.each{ |key, matches|
        assign_action_reject(T.must(diff.tags[key]), options: { 'sources' => matches.collect{ |m| m[-1].sources }.flatten.compact.presence }.compact.presence)
      }

      (diff.tags.keys - matcheses.keys).each{ |key, _matches|
        assign_action_accept(T.must(diff.tags[key]))
      }
    end
  end
end
