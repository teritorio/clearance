# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/tags_matches'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  class AfterDelay < Validator
    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        retention_delay: Integer,
        description: T.nilable(String),
        action: T.nilable(Validation::ActionType),
        action_force: T.nilable(Validation::ActionType),
        now: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, retention_delay:, description: nil, action: nil, action_force: nil, now: nil)
      super(id: id, osm_tags_matches: osm_tags_matches, description: description, action: action, action_force: action_force)
      now = now.nil? ? Time.now.utc : now.to_datetime
      @expire_date = T.let((now - retention_delay.seconds).to_s, String)
    end

    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply(_before, after, diff)
      return if after.nil?

      return if after.created >= @expire_date

      diff.tags.each_value{ |tag_diff|
        assign_action(tag_diff)
      }
    end
  end
end
