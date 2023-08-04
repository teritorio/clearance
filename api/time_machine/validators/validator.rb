# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/types'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class ValidatorBase
    extend T::Sig
    sig {
      params(
        id: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, description: nil)
      @id = id
      @description = description
    end

    sig {
      overridable.params(
        _before: T.nilable(ChangesDb::OSMChangeProperties),
        _after: ChangesDb::OSMChangeProperties,
        _diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(_before, _after, _diff); end

    sig {
      returns(T::Hash[T.untyped, T.untyped])
    }
    def to_h
      instance_variables.select{ |v| [:@watches].exclude?(v) }.to_h { |v|
        [v.to_s.delete('@'), instance_variable_get(v)]
      }
    end
  end

  class Validator < ValidatorBase
    extend T::Sig
    sig {
      params(
        id: String,
        description: T.nilable(String),
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
      ).void
    }
    def initialize(id:, description: nil, action: nil, action_force: nil)
      super(id: id)
      @action_force = T.let(!action_force.nil?, T::Boolean)
      @action = T.let(Types::Action.new(
        validator_id: id,
        description: description,
        action: action || action_force || 'reject'
      ), Types::Action)
    end

    sig {
      params(
        actions: T::Array[Types::Action],
        value: T.nilable(Types::Action),
        options: T.nilable(T::Hash[String, T.untyped]),
      ).void
    }
    def assign_action(actions, value: nil, options: nil)
      # Side effect in actions
      actions.clear if @action_force
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

  class ValidatorDual < ValidatorBase
    extend T::Sig
    sig {
      params(
        id: String,
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, accept:, reject:, description: nil)
      super(id: id)
      @action_accept = T.let(Types::Action.new(
        validator_id: accept,
        description: description,
        action: 'accept'
      ), Types::Action)
      @action_reject = T.let(Types::Action.new(
        validator_id: reject,
        description: description,
        action: 'reject'
      ), Types::Action)
    end

    sig {
      params(
        actions: T::Array[Types::Action],
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
        actions: T::Array[Types::Action],
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
  class All < Validator
    sig {
      override.params(
        _before: T.nilable(ChangesDb::OSMChangeProperties),
        _after: ChangesDb::OSMChangeProperties,
        diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(_before, _after, diff)
      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end
