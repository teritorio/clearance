# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/tags_matches'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class TagsChanges < ValidatorDual
    sig { returns(Osm::TagsMatches) }
    attr_reader :osm_tags_matches

    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
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
        before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply(before, after, diff)
      matcheses = (
        (before && @osm_tags_matches.match_with_extra(before['tags']) || []) +
        @osm_tags_matches.match_with_extra(after&.dig('tags') || {})
      ).group_by(&:first).select{ |key, _match|
        diff.tags.key?(key)
      }

      matcheses.each{ |key, matches|
        assign_action_reject(T.must(diff.tags[key]), options: { 'sources' => matches.collect{ |m| m[-1].sources }.flatten.compact.presence }.compact.presence)
      }

      (diff.tags.keys - matcheses.keys).each{ |key|
        assign_action_accept(T.must(diff.tags[key]))
      }
    end
  end
end
