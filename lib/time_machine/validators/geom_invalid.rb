# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class GeomInvalid < ValidatorLink
    sig {
      override.params(
        before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply_link(before, after, diff)
      return if after.nil?

      after_geos = T.unsafe(after.geos)

      if after_geos.nil?
        if !after.deleted
          attribs_geom = diff.attribs['geom'] ||= []
          assign_action(attribs_geom, options: { 'reason' => 'Fails to build geometry' })
        end

        return
      end

      after_geos_invalid = after_geos.invalid_reason
      return if after_geos_invalid.nil?

      # Both before and after are invalid, no change => accept
      before_geos = T.unsafe(before&.geos)
      return if !before.nil? && !before.deleted && !before_geos&.invalid_reason.nil?

      attribs_geom = diff.attribs['geom'] ||= []
      assign_action(attribs_geom, options: { 'reason' => after_geos_invalid })
    end
  end
end
