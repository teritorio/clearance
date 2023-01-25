# frozen_string_literal: true
# typed: true

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
      @action = Types::Action.new(
        validator_id: id,
        description: description,
        action: action || action_force || 'reject'
      )
    end

    sig {
      params(
        actions: T::Array[Types::Action],
        value: T.nilable(Types::Action),
      ).void
    }
    def assign_action(actions, value = nil)
      # Side effect in actions
      actions.clear if @action_force
      actions << (value || @action)
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
      @action_accept = Types::Action.new(
        validator_id: accept,
        description: description,
        action: 'accept'
      )
      @action_reject = Types::Action.new(
        validator_id: reject,
        description: description,
        action: 'reject'
      )
    end

    sig {
      params(
        actions: T::Array[Types::Action],
      ).void
    }
    def assign_action_accept(actions)
      # Side effect in actions
      actions << @action_accept
    end

    sig {
      params(
        actions: T::Array[Types::Action],
      ).void
    }
    def assign_action_reject(actions)
      # Side effect in actions
      actions << @action_reject
    end
  end

  # Dummy Validator
  class All < Validator
    def apply(_before, _after, diff)
      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end
