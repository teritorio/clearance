# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/types'
require './time_machine/watches'

module Validators
  extend T::Sig

  class GeomNewObject < Validator
    sig {
      params(
        id: String,
        watches: T::Hash[String, Types::Watch],
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, action: nil, action_force: nil, description: nil)
      super(id: id, watches: watches, action: action, action_force: action_force, description: description)
    end

    def apply(before, _after, diff)
      %w[lon lat nodes members].each{ |attrib|
        assign_action(diff.attrib[attrib]) if !before && diff.attrib[attrib]
      }
    end
  end
end
