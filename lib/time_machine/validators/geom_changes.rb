# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class GeomChanges < ValidatorDual
    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        accept: String,
        reject: String,
        dist: T.any(Float, Integer),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, accept:, reject:, dist:, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, accept: accept, reject: reject, description: description)
      @dist = dist
    end

    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        _after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
        conflation_reason: OSMLogicalHistory::Conflation::ConflationReason,
      ).void
    }
    def apply(_before, _after, diff, conflation_reason)
      dist = T.cast(conflation_reason.geom&.dig(:max_distance), T.nilable(Float))
      return if !dist || dist == 0

      attribs_geom = diff.attribs['geom'] ||= []
      if dist < @dist
        assign_action_accept(attribs_geom, options: { 'dist' => dist })
      else
        assign_action_reject(attribs_geom, options: { 'dist' => dist })
      end
    end
  end
end
