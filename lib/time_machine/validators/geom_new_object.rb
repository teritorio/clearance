# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class GeomNewObject < Validator
    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        action: T.nilable(Validation::ActionType),
        action_force: T.nilable(Validation::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, action: nil, action_force: nil, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, action: action, action_force: action_force, description: description)
    end

    sig {
      override.params(
        before: T.nilable(Validation::OSMChangeProperties),
        _after: Validation::OSMChangeProperties,
        diff: Validation::DiffActions,
      ).void
    }
    def apply(before, _after, diff)
      %w[geom_distance].each{ |attrib|
        assign_action(T.must(diff.attribs[attrib])) if !before && !diff.attribs[attrib].nil?
      }
    end
  end
end
