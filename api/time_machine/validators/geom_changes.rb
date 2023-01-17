# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/types'
require './time_machine/watches'

module Validators
  extend T::Sig

  class GeomChanges < Validator
    sig {
      params(
        id: String,
        watches: T::Hash[String, Types::Watch],
        dist: T.any(Float, Integer),
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, dist:, action: nil, action_force: nil, description: nil)
      super(id: id, watches: watches, action: action, action_force: action_force, description: description)
      @dist = dist
    end

    def apply(before, after, diff)
      # TODO, impl for ways (and relations)
      return if !before || !diff.attribs['change_distance']

      dist = after['change_distance']
      return if !(@dist < 0 && dist < @dist.abs) && !(@dist > 0 && dist > @dist)

      assign_action(diff.attribs['lon']) if diff.attribs['lon']
      assign_action(diff.attribs['lat']) if diff.attribs['lat']
      assign_action(diff.attribs['change_distance'])
    end
  end
end
