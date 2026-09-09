# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class UserNew < ValidatorLink
    extend T::Sig

    class Settings < ValidatorBase::Settings
      const :description, String, override: true, default: 'First changes made by an user.'
    end

    extend T::Generic

    SettingsType = type_member{ { upper: Settings } }

    sig {
      params(
        settings: SettingsType,
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

      days = after.osm_user&.account_created.nil? ? nil : after.created.to_datetime.to_date - T.must(after.osm_user&.account_created).to_datetime.to_date
      changesets_count = after.osm_user&.changesets_count.nil? ? nil : T.must(after.osm_user&.changesets_count)
      return if (days.nil? || days > @min_days) && (changesets_count.nil? || changesets_count > @min_changesets)

      attribs_username = diff.attribs['username'] ||= []
      assign_action(attribs_username, options: {
        'contribution_made_n_days_after_account_created' => days,
        'current_changesets_count_since_account_created' => changesets_count,
      })
    end
  end
end
