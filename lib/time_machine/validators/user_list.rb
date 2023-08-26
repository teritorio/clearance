# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/types'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class UserList < Validator
    sig {
      params(
        id: String,
        osm_tags_matches: OsmTagsMatches::OsmTagsMatches,
        list: T::Array[String],
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, list:, action: nil, action_force: nil, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, action: action, action_force: action_force, description: description)
      @list = list
    end

    sig {
      override.params(
        _before: T.nilable(ChangesDb::OSMChangeProperties),
        after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(_before, after, diff)
      return if @list.exclude?(after['username'])

      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end