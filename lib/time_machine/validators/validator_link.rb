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
        _proj: Integer,
        prevalidation_clusters: T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]],
      ).returns(T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]])
    }
    def apply(_conn, _proj, prevalidation_clusters)
      prevalidation_clusters.collect{ |accepted_links, conflations_matches|
        conflations_matches.each{ |link|
          apply_link(link.conflation.before, link.conflation.after, link.result.diff)
        }
        [accepted_links, conflations_matches]
      }
    end

    sig {
      params(
        _before: T.nilable(Validation::OSMChangeProperties),
        _after: T.nilable(Validation::OSMChangeProperties),
        _diff: Validation::DiffActions,
      ).void
    }
    def apply_link(_before, _after, _diff); end
  end

  class ValidatorLink < ValidatorLinkBase
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
      super(id: id, osm_tags_matches: osm_tags_matches, description: description)
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

  class ValidatorLinkDual < ValidatorLinkBase
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
      super(id: id, osm_tags_matches: osm_tags_matches, description: description)
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
  class All < ValidatorLink
    extend T::Sig

    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        description: T.nilable(String),
        action: T.nilable(Validation::ActionType),
        action_force: T.nilable(Validation::ActionType),
        block: T.nilable(T.proc.params(
          before: T.nilable(Validation::OSMChangeProperties),
          after: T.nilable(Validation::OSMChangeProperties),
          diff: Validation::DiffActions,
        ).returns(T::Boolean))
      ).void
    }
    def initialize(id:, osm_tags_matches:, description: nil, action: nil, action_force: nil, &block)
      super

      @block = block
    end

    sig {
      override.params(
        before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
      ).void
    }
    def apply_link(before, after, diff)
      if @block && !@block.call(before, after, diff)
        return
      end

      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end
end
