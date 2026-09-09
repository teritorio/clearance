# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class UserBlock < ValidatorLink
    extend T::Sig

    class Settings < ValidatorBase::Settings
      const :description, String, override: true, default: 'Change made by an user currently blocked, or with too much previous blocks.'
      const :max_blocks_received, Integer, default: 2
      const :max_blocks_active, Integer, default: 1
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

      return unless (!after.osm_user&.blocks_received_active.nil? && T.must(after.osm_user&.blocks_received_active) >= @settings.max_blocks_active) ||
                    (!after.osm_user&.blocks_received_count.nil? && T.must(after.osm_user&.blocks_received_count) >= @settings.max_blocks_received)

      attribs_username = diff.attribs['username'] ||= []
      assign_action(attribs_username)
    end
  end
end
