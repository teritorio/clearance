# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/types'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class GeomChanges < Validator
    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        dist: T.any(Float, Integer),
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, dist:, action: nil, action_force: nil, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, action: action, action_force: action_force, description: description)
      @dist = dist
    end

    sig {
      override.params(
        before: T.nilable(ChangesDb::OSMChangeProperties),
        after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(before, after, diff)
      return if !before || !diff.attribs['geom_distance']

      dist = after['geom_distance']
      return if !(@dist < 0 && dist < @dist.abs) && !(@dist > 0 && dist > @dist)

      assign_action(diff.attribs['geom_distance'] || [], options: { 'dist' => dist })
    end
  end
end
