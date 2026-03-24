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
        before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply_link(before, after, diff)
      return if !before || !diff.attribs['geom_distance'] || diff.attribs['geom_distance'] == 0

      return if after.nil? || !after.geom_distance

      dist = after.geom_distance
      return if dist.nil?

      if dist < @dist
        assign_action_accept(diff.attribs['geom_distance'] || [], options: { 'dist' => dist })
      else
        assign_action_reject(diff.attribs['geom_distance'] || [], options: { 'dist' => dist })
      end
    end
  end
end
