# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator'

module Validators
  extend T::Sig

  # tout flagger en reject pendant un délai
  # Accept auto after delay

  class Delayed < Validator
    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        before_delay: T.nilable(Integer),
        after_delay: T.nilable(Integer),
        action: T.nilable(Validation::ActionType),
        action_force: T.nilable(Validation::ActionType),
        description: T.nilable(String),
        now: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, before_delay: nil, after_delay: nil, action: nil, action_force: nil, description: nil, now: nil)
      raise "At least one of 'before_delay' or 'after_delay' should be declared in #{id}" if before_delay.nil? && after_delay.nil?
      raise "At least one of 'action' or 'action_force' should be declared in #{id}" if action.nil? && action_force.nil?

      super(id: id, osm_tags_matches: osm_tags_matches, description: description, action: action, action_force: action_force)
      now_time = now.nil? ? Time.now.utc : Time.parse(now).utc
      @before_thresold = T.let(before_delay.nil? ? nil : (now_time - before_delay).iso8601, T.nilable(String))
      @after_thresold = T.let(after_delay.nil? ? nil : (now_time - after_delay).iso8601, T.nilable(String))
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


      if !@before_thresold.nil? && after.created >= @before_thresold
        diff.attribs.each_value { |action|
          assign_action(action)
        }
        diff.tags.each_value { |action|
          assign_action(action)
        }
      end

      return unless !@after_thresold.nil? && @after_thresold >= after.created

      diff.attribs.each_value { |action|
        assign_action(action)
      }
      diff.tags.each_value { |action|
        assign_action(action)
      }
    end
  end
end
