# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/types'
require 'active_support'
require 'active_support/core_ext'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class Deleted < Validator
    sig {
      override.params(
        _before: T.nilable(ChangesDb::OSMChangeProperties),
        after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(_before, after, diff)
      return if !after['deleted']

      diff.attribs.each { |_key, action|
        assign_action(action)
      }
      diff.tags.each { |_key, action|
        assign_action(action)
      }
    end
  end
end
