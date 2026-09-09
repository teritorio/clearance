# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class GeomChanges < ValidatorLinkDual
    extend T::Sig

    class Settings < ValidatorBase::Settings
      const :description, String, override: true, default: 'Reject geometry changed more that a threshold distance (in meter).'
      const :euclidian_distance, T.any(Float, Integer)
    end

    extend T::Generic

    SettingsType = type_member{ { upper: Settings } }

    sig { returns(T.nilable(String)) }
    def self.default_description
      'Reject geometry changed more that a threshold distance (in meter).'
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
      euclidian_distance = T.cast(conflation_reason.geom&.dig(:max_distance), T.nilable(Float))
      return if !euclidian_distance || euclidian_distance == 0

      max_geom_change_euclidian_distance = osm_tags_matches.matches.collect{ |match| match.validation&.geom_change_euclidian_distance }.max
      threshold_euclidian_distance = max_geom_change_euclidian_distance || @settings.euclidian_distance

      attribs_geom = diff.attribs['geom'] ||= []
      if euclidian_distance < threshold_euclidian_distance
        assign_action_accept(attribs_geom, options: { 'euclidian_distance' => euclidian_distance })
      else
        assign_action_reject(attribs_geom, options: { 'euclidian_distance' => euclidian_distance })
      end
    end
  end
end
