# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class GeomChanges < ValidatorLinkDual
    sig {
      params(
        settings: ValidatorBase::Settings,
        accept: String,
        reject: String,
        dist: T.any(Float, Integer),
      ).void
    }
    def initialize(settings:, accept:, reject:, dist:)
      super(settings: settings, accept: accept, reject: reject)
      @dist = dist
    end

    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        _after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
        conflation_reason: OSMLogicalHistory::Conflation::ConflationReason,
      ).void
    }
    def apply_link(_before, _after, diff, conflation_reason)
      dist = T.cast(conflation_reason.geom&.dig(:max_distance), T.nilable(Float))
      return if !dist || dist == 0

      attribs_geom = diff.attribs['geom'] ||= []
      if dist < @dist
        assign_action_accept(attribs_geom, options: { 'dist' => dist })
      else
        assign_action_reject(attribs_geom, options: { 'dist' => dist })
      end
    end
  end
end
