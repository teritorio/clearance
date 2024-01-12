# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class GeomChanges < Validator
    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        dist: T.nilable(T.any(Float, Integer)),
        action: T.nilable(Validation::ActionType),
        action_force: T.nilable(Validation::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, dist: nil, action: nil, action_force: nil, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, action: action, action_force: action_force, description: description)
      @dist = dist
    end

    sig {
      override.params(
        before: T.nilable(Validation::OSMChangeProperties),
        after: Validation::OSMChangeProperties,
        diff: Validation::DiffActions,
      ).void
    }
    def apply(before, after, diff)
      return if !before || !diff.attribs['geom_distance']

      if @dist.nil?
        assign_action(diff.attribs['geom_distance'] || [])
      else
        dist = after['geom_distance']
        return if !(@dist < 0 && dist < @dist.abs) && !(@dist > 0 && dist > @dist)

        assign_action(diff.attribs['geom_distance'] || [], options: { 'dist' => dist })
      end
    end
  end
end
