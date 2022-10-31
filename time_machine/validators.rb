# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './types'


module Validators
  include Types
  extend T::Sig

  class Validator
    extend T::Sig
    sig {
      params(
        id: String,
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, action: nil, action_force: nil, description: nil)
      @action_force = T.let(!action_force.nil?, T::Boolean)
      @action = Types::Action.new(
        validator_id: id,
        description:,
        action: action || action_force || 'reject'
      )
    end

    sig { params(actions: T::Array[Types::Action]).void }
    def assign_action(actions)
      # Side effect in actions
      actions.clear if @action_force
      actions << @action
    end

    sig {
      params(
        _before: T.nilable(ChangesDB::OSMChangeProperties),
        _after: ChangesDB::OSMChangeProperties,
        _diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(_before, _after, _diff); end
  end

  # Dummy Validator
  class All < Validator
    def apply(_before, _after, diff)
      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end

  class UserList < Validator
    sig {
      params(
        id: String,
        list: T::Array[String],
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, list:, action: nil, action_force: nil, description: nil)
      super(id:, action:, action_force:, description:)
      @list = list
    end

    def apply(_before, after, diff)
      return if !@list.include?(after['username'])

      (diff.attribs.values + diff.tags.values).each{ |action|
        assign_action(action)
      }
    end
  end

  class GeomNewObject < Validator
    sig {
      params(
        id: String,
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, action: nil, action_force: nil, description: nil)
      super(id:, action:, action_force:, description:)
    end

    def apply(before, _after, diff)
      %w[lon lat nodes members].each{ |attrib|
        assign_action(diff.attrib[attrib]) if !before && diff.attrib[attrib]
      }
    end
  end

  class GeomChanges < Validator
    sig {
      params(
        id: String,
        dist: Float,
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, dist:, action: nil, action_force: nil, description: nil)
      super(id:, action:, action_force:, description:)
      @dist = dist
    end

    def dist(before, after)
      # TODO, make a real impl
      (before['lon'] - after['lon']).abs + (before['lat'] - after['lat']).abs
    end

    def apply(before, after, diff)
      # TODO, impl for ways (and relations)
      return if !before || !(diff.attribs['lat'] || diff.attribs['lon'])

      dist = dist(before, after)
      return if !(@dist < 0 && dist < @dist.abs) && !(@dist > 0 && dist > @dist)

      assign_action(diff.attribs['lon']) if diff.attribs['lon']
      assign_action(diff.attribs['lat']) if diff.attribs['lat']
    end
  end

  class TagsChanges < Validator
    sig {
      params(
        id: String,
        tags: T::Array[String],
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, tags:, action: nil, action_force: nil, description: nil)
      super(id:, action:, action_force:, description:)
      @tags = tags
    end

    def apply(_before, _after, diff)
      @tags.intersection(diff.tags.keys).each{ |tag|
        assign_action(diff.tags[tag])
      }
    end
  end

  class Deleted < Validator
    def apply(_before, after, diff)
      assign_action(diff.attribs['deleted']) if after['deleted']
    end
  end

  # Adapted from activesupport/lib/active_support/inflector/methods.rb, line 69
  sig { params(term: String).returns(String) }
  def self.camelize(term)
    string = term.to_s
    string = string.sub(/^[a-z\d]*/, &:capitalize)
    string.gsub!(%r{(?:_|(/))([a-z\d]*)}) { "#{Regexp.last_match(1)}#{T.must(Regexp.last_match(2)).capitalize}" }
    string.gsub!('/', '::')
    string
  end

  sig { params(validators_config: T::Hash[String, T::Hash[String, Object]]).returns(T::Array[Validator]) }
  def self.validators_factory(validators_config)
    validators_config.collect{ |id, config|
      class_name = T.cast(config['instance'], T.nilable(String)) || "Validators::#{camelize(id)}"
      args = config.except('instance').transform_keys(&:to_sym)
      Object.const_get(class_name).new(id:, **args)
    }
  end
end
