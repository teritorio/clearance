# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class GeomNewObject < Validator
    sig {
      override.params(
        before: T.nilable(Validation::OSMChangeProperties),
        _after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply(before, _after, diff)
      %w[geom_distance members].each{ |attrib|
        assign_action(T.must(diff.attribs[attrib])) if !before && !diff.attribs[attrib].nil?
      }
    end
  end
end
