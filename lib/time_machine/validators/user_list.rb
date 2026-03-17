# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  class UserList < ValidatorLink
    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        list: T::Array[String],
        action: T.nilable(Validation::ActionType),
        action_force: T.nilable(Validation::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, list:, action: nil, action_force: nil, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, action: action, action_force: action_force, description: description)
      @list = list
    end

    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply_link(_before, after, diff)
      return if after.nil? || @list.exclude?(after.username)

      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end
