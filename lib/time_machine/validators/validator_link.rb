# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_base'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class ValidatorLinkBase < ValidatorBase
    extend T::Sig

    sig {
      params(
        _conn: T.nilable(PG::Connection),
        _locha_id: Integer,
        prevalidation_clusters: T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]],
      ).returns(T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]])
    }
    def apply(_conn, _locha_id, prevalidation_clusters)
      prevalidation_clusters.collect{ |accepted_links, conflations_matches|
        conflations_matches.each{ |link|
          apply_link(link.conflation.before, link.conflation.after, link.result.diff, link.conflation.conflation_reason)
        }
        [accepted_links, conflations_matches]
      }
    end

    sig {
      params(
        _before: T.nilable(Validation::OSMChangeProperties),
        _after: T.nilable(Validation::OSMChangeProperties),
        _diff: Validation::DiffActions,
        _conflation_reason: OSMLogicalHistory::Conflation::ConflationReason,
      ).void
    }
    def apply_link(_before, _after, _diff, _conflation_reason); end

    sig {
      returns(T::Hash[T.untyped, T.untyped])
    }
    def to_h
      instance_variables.select{ |v| [:@osm_tags_matches].exclude?(v) }.to_h { |v|
        [v.to_s.delete('@'), instance_variable_get(v)]
      }
    end
  end

  class ValidatorLink < ValidatorLinkBase
    extend T::Sig

    sig {
      params(
        settings: ValidatorBase::Settings,
        action: T.nilable(Validation::ActionType),
      ).void
    }
    def initialize(settings:, action: nil)
      super(settings: settings)
      @action = T.let(Validation::Action.new(
        validator_id: settings.id,
        description: settings.description,
        action: action&.split('_')&.last || 'reject',
        force: action&.start_with?('force_') || false,
      ), Validation::Action)
    end

    sig {
      params(
        actions: T::Array[Validation::Action],
        value: T.nilable(Validation::Action),
        options: T.nilable(T::Hash[String, T.untyped]),
      ).void
    }
    def assign_action(actions, value: nil, options: nil)
      # Side effect in actions
      actions.clear if @action.force
      if value
        actions << value
      else
        action = @action
        if options
          action = @action.dup
          action.options = options
        end
        actions << action
      end
    end
  end

  class ValidatorLinkDual < ValidatorLinkBase
    extend T::Sig

    sig {
      params(
        settings: ValidatorBase::Settings,
        actions: T::Hash[String, String],
      ).void
    }
    def initialize(settings:, actions:)
      super(settings: settings)
      if actions.key?('accept') || actions.key?('force_accept')
        @action_accept = T.let(Validation::Action.new(
          validator_id: T.must(actions['accept']),
          description: settings.description,
          action: 'accept',
          force: actions.key?('force_accept'),
        ), Validation::Action)
      end
      return unless actions.key?('reject') || actions.key?('force_reject')

      @action_reject = T.let(Validation::Action.new(
        validator_id: T.must(actions['reject']),
        description: settings.description,
        action: 'reject',
        force: actions.key?('force_reject'),
      ), Validation::Action)
    end

    sig {
      params(
        actions: T::Array[Validation::Action],
        options: T.nilable(T::Hash[String, T.untyped]),
      ).void
    }
    def assign_action_accept(actions, options: nil)
      # Side effect in actions

      action = @action_accept
      if options
        action = action.dup
        action.options = options
      end

      actions << action
    end

    sig {
      params(
        actions: T::Array[Validation::Action],
        options: T.nilable(T::Hash[String, T.untyped]),
      ).void
    }
    def assign_action_reject(actions, options: nil)
      # Side effect in actions

      action = @action_reject
      if options
        action = action.dup
        action.options = options
      end

      actions << action
    end
  end

  # Dummy Validator
  class All < ValidatorLink
    extend T::Sig

    sig {
      params(
        settings: ValidatorBase::Settings,
        action: T.nilable(Validation::ActionType),
        block: T.nilable(T.proc.params(
          before: T.nilable(Validation::OSMChangeProperties),
          after: T.nilable(Validation::OSMChangeProperties),
          diff: Validation::DiffActions,
        ).returns(T::Boolean))
      ).void
    }
    def initialize(settings:, action: nil, &block)
      super(settings: settings, action: action)

      @block = block
    end

    sig {
      override.params(
        before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
        _conflation_reason: OSMLogicalHistory::Conflation::ConflationReason,
      ).void
    }
    def apply_link(before, after, diff, _conflation_reason)
      if @block && !@block.call(before, after, diff)
        return
      end

      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end
