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
      const :before_delay, T.nilable(Integer)
      const :after_delay, T.nilable(Integer)
    end

    extend T::Generic

    SettingsType = type_member{ { upper: Settings } }

    sig {
      params(
        settings: SettingsType,
        action: T.nilable(Validation::ActionType),
        now: T.nilable(String),
      ).void
    }
    def initialize(settings:, action: nil, now: nil)
      super(settings: settings, action: action)
      raise "At least one of 'before_delay' or 'after_delay' should be declared in #{settings.id}" if @settings.before_delay.nil? && @settings.after_delay.nil?

      now_time = now.nil? ? Time.now.utc : Time.parse(now).utc
      @before_thresold = T.let(@settings.before_delay.nil? ? nil : (now_time - @settings.before_delay).iso8601, T.nilable(String))
      @after_thresold = T.let(@settings.after_delay.nil? ? nil : (now_time - @settings.after_delay).iso8601, T.nilable(String))
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
