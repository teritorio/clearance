# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class ValidatorBase
    extend T::Sig

    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, description: nil)
      @id = id
      @osm_tags_matches = osm_tags_matches
      @description = description
    end

    sig {
      overridable.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        _after: T.nilable(Validation::OSMChangeProperties),
        _diff: Validation::DiffActions,
      ).void
    }
    def apply(_before, _after, _diff); end

    sig {
      returns(T::Hash[T.untyped, T.untyped])
    }
    def to_h
      instance_variables.select{ |v| [:@osm_tags_matches].exclude?(v) }.to_h { |v|
        [v.to_s.delete('@'), instance_variable_get(v)]
      }
    end
  end

  class Validator < ValidatorBase
    extend T::Sig

    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        description: T.nilable(String),
        action: T.nilable(Validation::ActionType),
        action_force: T.nilable(Validation::ActionType),
      ).void
    }
    def initialize(id:, osm_tags_matches:, description: nil, action: nil, action_force: nil)
      super(id: id, osm_tags_matches: osm_tags_matches)
      @action_force = T.let(!action_force.nil?, T::Boolean)
      @action = T.let(Validation::Action.new(
        validator_id: id,
        description: description,
        action: action || action_force || 'reject'
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
        osm_tags_matches: Osm::TagsMatches,
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, accept:, reject:, description: nil)
      super(id: id, osm_tags_matches: osm_tags_matches)
      @action_accept = T.let(Validation::Action.new(
        validator_id: accept,
        description: description,
        action: 'accept'
      ), Validation::Action)
      @action_reject = T.let(Validation::Action.new(
        validator_id: reject,
        description: description,
        action: 'reject'
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
  class All < Validator
    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        _after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply(_before, _after, diff)
      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end
