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
        before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply(before, after, diff)
      return if !before || ((!diff.attribs['geom_distance'] || diff.attribs['geom_distance'] == 0) && !diff.attribs['members'])

      return unless !after.nil? && after.geom_distance

      dist = after.geom_distance
      return if dist.nil?

      if dist < @dist
        assign_action_accept(diff.attribs['geom_distance'] || [], options: { 'dist' => dist })
      else
        assign_action_reject(diff.attribs['geom_distance'] || [], options: { 'dist' => dist })
      end
    end
  end
end
