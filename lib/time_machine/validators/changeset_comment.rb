# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require 'active_support'
require 'active_support/core_ext'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class ChangesetComment < ValidatorLink
    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
        _conflation_reason: OSMLogicalHistory::Conflation::ConflationReason,
      ).void
    }
    def apply_link(_before, after, diff, _conflation_reason)
      return if after.nil?

      return if after.changeset&.comments_count.blank? || after.changeset&.comments_count&.zero?

      attribs_changeset = diff.attribs['changeset'] ||= []
      assign_action(attribs_changeset)
    end
  end
end
