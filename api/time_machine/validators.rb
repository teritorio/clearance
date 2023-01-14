# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/types'
require './time_machine/watches'


module Validators
  extend T::Sig

  class ValidatorBase
    extend T::Sig
    sig {
      params(
        id: String,
        watches: T::Hash[String, Types::Watch],
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, description: nil)
      @id = id
      @watches = watches
      @description = description
    end

    sig {
      params(
        _before: T.nilable(ChangesDb::OSMChangeProperties),
        _after: ChangesDb::OSMChangeProperties,
        _diff: TimeMachine::DiffActions,
      ).void
    }
    def apply(_before, _after, _diff); end

    def to_h
      instance_variables.select{ |v| ![:@watches].include?(v) }.to_h { |v|
        [v.to_s.delete('@'), instance_variable_get(v)]
      }
    end
  end

  class Validator < ValidatorBase
    extend T::Sig
    sig {
      params(
        id: String,
        watches: T::Hash[String, Types::Watch],
        description: T.nilable(String),
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
      ).void
    }
    def initialize(id:, watches:, description: nil, action: nil, action_force: nil)
      super(id: id, watches: watches)
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
        watches: T::Hash[String, Types::Watch],
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, accept:, reject:, description: nil)
      super(id: id, watches: watches)
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

  class UserList < Validator
    sig {
      params(
        id: String,
        watches: T::Hash[String, Types::Watch],
        list: T::Array[String],
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, list:, action: nil, action_force: nil, description: nil)
      super(id: id, watches: watches, action: action, action_force: action_force, description: description)
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
        watches: T::Hash[String, Types::Watch],
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, action: nil, action_force: nil, description: nil)
      super(id: id, watches: watches, action: action, action_force: action_force, description: description)
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
        watches: T::Hash[String, Types::Watch],
        dist: T.any(Float, Integer),
        action: T.nilable(Types::ActionType),
        action_force: T.nilable(Types::ActionType),
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, dist:, action: nil, action_force: nil, description: nil)
      super(id: id, watches: watches, action: action, action_force: action_force, description: description)
      @dist = dist
    end

    def apply(before, after, diff)
      # TODO, impl for ways (and relations)
      return if !before || !diff.attribs['change_distance']

      dist = after['change_distance']
      return if !(@dist < 0 && dist < @dist.abs) && !(@dist > 0 && dist > @dist)

      assign_action(diff.attribs['lon']) if diff.attribs['lon']
      assign_action(diff.attribs['lat']) if diff.attribs['lat']
      assign_action(diff.attribs['change_distance'])
    end
  end

  class TagsChanges < ValidatorDual
    sig {
      params(
        id: String,
        watches: T::Hash[String, Types::Watch],
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, accept:, reject:, description: nil)
      super(id: id, watches: watches, accept: accept, reject: reject, description: description)
    end

    def apply(before, after, diff)
      match_keys = (
        (before && Watches.match_osm_filters_tags(@watches, before['tags']) || []) +
        Watches.match_osm_filters_tags(@watches, after['tags'])
      ).intersection(diff.tags.keys).select{ |tag|
        # Exclude new tags with insignificant value
        !(!before['tags'].include?(tag) && after['tags'].include?(tag) && after['tags'][tag] == 'no')
      }
      match_keys.each{ |key|
        assign_action_reject(diff.tags[key])
      }
      (diff.tags.keys - match_keys).each{ |key|
        assign_action_accept(diff.tags[key])
      }
    end
  end

  class Deleted < Validator
    def apply(_before, after, diff)
      return if !after['deleted']

      diff.attribs.each { |_key, action|
        assign_action(action)
      }
      diff.tags.each { |_key, action|
        assign_action(action)
      }
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

  sig {
    params(
      validators_config: T::Hash[String, T::Hash[String, Object]],
      watches: T::Hash[String, Types::Watch],
    ).returns(T::Array[ValidatorBase])
  }
  def self.validators_factory(validators_config, watches)
    validators_config.collect{ |id, config|
      class_name = T.cast(config['instance'], T.nilable(String)) || "Validators::#{camelize(id)}"
      args = config.except('instance').transform_keys(&:to_sym)
      Object.const_get(class_name).new(id: id, watches: watches, **args)
    }
  end
end
