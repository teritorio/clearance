# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class UserNew < ValidatorLink
    sig {
      params(
        settings: ValidatorBase::Settings,
        min_changesets: Integer,
        min_days: Integer,
        action: T.nilable(Validation::ActionType),
      ).void
    }
    def initialize(settings:, min_changesets: 5, min_days: 5, action: nil)
      super(settings: settings, action: action)
      @min_changesets = min_changesets
      @min_days = min_days
    end

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

      return unless (!after.osm_user&.account_created.nil? && (after.created.to_datetime.utc - T.must(after.osm_user&.account_created).to_datetime.utc).days >= @min_days) ||
                    (!after.osm_user&.changesets_count.nil? && T.must(after.osm_user&.changesets_count) >= @min_changesets)

      attribs_username = diff.attribs['username'] ||= []
      assign_action(attribs_username)
    end
  end
end
