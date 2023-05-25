# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/types'
require './time_machine/validators/validator'

module Validators
  extend T::Sig

  class GeomNewObject < Validator
    sig {
      params(
        id: String,
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, action: nil, action_force: nil, description: nil)
      super(id: id, action: action, action_force: action_force, description: description)
    end

    sig {
      override.params(
        before: T.nilable(ChangesDb::OSMChangeProperties),
        _after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(before, _after, diff)
      %w[lon lat nodes members].each{ |attrib|
        assign_action(T.must(diff.attribs[attrib])) if !before && !diff.attribs[attrib].nil?
      }
    end
  end
end
