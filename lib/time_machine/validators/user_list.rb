# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class UserList < ValidatorLink
    sig {
      params(
        settings: ValidatorBase::Settings,
        list: T::Array[String],
        action: T.nilable(Validation::ActionType),
        action_force: T.nilable(Validation::ActionType),
      ).void
    }
    def initialize(settings:, list:, action: nil, action_force: nil)
      super(settings: settings, action: action, action_force: action_force)
      @list = list
    end

    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply_link(_before, after, diff)
      return if after.nil? || @list.exclude?(after.username)

      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end
