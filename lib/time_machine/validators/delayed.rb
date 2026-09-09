# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

module Validators
  extend T::Sig

  # tout flagger en reject pendant un délai
  # Accept auto after delay

  class Delayed < ValidatorLink
    extend T::Sig

    class Settings < ValidatorBase::Settings
      const :description, String, override: true, default: 'Accept or reject changes after a delay.'
    end

    extend T::Generic

    SettingsType = type_member{ { upper: Settings } }

    sig {
      params(
        settings: SettingsType,
        before_delay: T.nilable(Integer),
        after_delay: T.nilable(Integer),
        action: T.nilable(Validation::ActionType),
        now: T.nilable(String),
      ).void
    }
    def initialize(settings:, before_delay: nil, after_delay: nil, action: nil, now: nil)
      raise "At least one of 'before_delay' or 'after_delay' should be declared in #{settings.id}" if before_delay.nil? && after_delay.nil?

      super(settings: settings, action: action)
      now_time = now.nil? ? Time.now.utc : Time.parse(now).utc
      @before_thresold = T.let(before_delay.nil? ? nil : (now_time - before_delay).iso8601, T.nilable(String))
      @after_thresold = T.let(after_delay.nil? ? nil : (now_time - after_delay).iso8601, T.nilable(String))
    end

    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
        _conflation_reason: OSMLogicalHistory::Conflation::ConflationReason,
      ).void
    }
    def apply_link(_before, after, diff, _conflation_reason)
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
