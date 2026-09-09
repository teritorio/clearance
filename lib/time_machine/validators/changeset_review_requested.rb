# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require 'active_support'
require 'active_support/core_ext'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class ChangesetReviewRequested < ValidatorLink
    extend T::Sig

    class Settings < ValidatorBase::Settings
      const :description, String, override: true, default: 'Changeset with review requested when submited.'
    end

    extend T::Generic

    SettingsType = type_member{ { upper: Settings } }

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

      return if after.changeset&.tags&.[]('review_requested') != 'yes'

      attribs_changeset = diff.attribs['changeset'] ||= []
      assign_action(attribs_changeset)
    end
  end
end
