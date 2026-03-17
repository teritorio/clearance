# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require 'active_support'
require 'active_support/core_ext'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class Deleted < ValidatorLink
    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply_link(_before, after, diff)
      return if !after.nil? && !after.deleted

      diff.attribs.each_value { |action|
        assign_action(action)
      }
      diff.tags.each_value { |action|
        assign_action(action)
      }
    end
  end
end
