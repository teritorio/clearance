# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/types'

module Validators
  extend T::Sig

  class UserList < Validator
    sig {
      params(
        id: String,
        list: T::Array[String],
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, list:, action: nil, action_force: nil, description: nil)
      super(id: id, action: action, action_force: action_force, description: description)
      @list = list
    end

    sig {
      override.params(
        _before: T.nilable(ChangesDb::OSMChangeProperties),
        after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(_before, after, diff)
      return if @list.exclude?(after['username'])

      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end
