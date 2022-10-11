# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './changes_db'
require './validators'
require './types'


module TimeMachine
  include Validators
  include Types
  extend T::Sig

  sig {
    params(
      before: T.nilable(ChangesDB::OSMChangeProperties),
      after: ChangesDB::OSMChangeProperties
    ).returns([HashActions, HashActions])
  }
  def self.diff_osm_object(before, after)
    diff_attribs = T.let({}, HashActions)
    diff_tags = T.let({}, HashActions)

    # Unchecked attribs
    # - version
    # - changeset
    # - uid
    # - username
    %w[lat lon nodes deleted members].each { |attrib|
      diff_attribs[attrib] = [] if (!before && after[attrib]) || before && before[attrib] != after[attrib]
    }

    ((before && before['tags'].keys || []) + after['tags'].keys).uniq.each{ |tag|
      diff_tags[tag] = [] if !before || before['tags'][tag] != after['tags'][tag]
    }

    [diff_attribs, diff_tags]
  end

  class ValidationResult < T::Struct
    const :action, T.nilable(Validators::ActionType)
    const :version, Integer
    const :diff_attribs, Validators::HashActions
    const :diff_tags, Validators::HashActions
  end

  sig {
    params(
      validators: T::Array[Validator],
      changes: T::Array[ChangesDB::OSMChangeProperties]
    ).returns(T::Array[ValidationResult])
  }
  def self.object_validation(validators, changes)
    before = T.let(nil, T.nilable(ChangesDB::OSMChangeProperties))
    afters = T.let([], T::Array[ChangesDB::OSMChangeProperties])
    if changes.size == 1
      afters = [changes[0]]
    elsif changes.size > 1
      before = changes[0]
      afters = changes[1..]
    end

    accepted_version = T.let(nil, T.nilable(ValidationResult))
    rejected_version = T.let(nil, T.nilable(ValidationResult))

    afters.reverse.each_with_index{ |after, index|
      diff_attribs, diff_tags = diff_osm_object(before, after)

      validators.each{ |validator|
        validator.apply(before, after, diff_attribs, diff_tags)
      }

      if !accepted_version
        fully_accepted = (
          (diff_attribs.empty? || diff_attribs.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } }) &&
          (diff_tags.empty? || diff_tags.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } })
        )

        if fully_accepted
          accepted_version = ValidationResult.new(
            action: 'accept',
            version: after['version'],
            diff_attribs:,
            diff_tags:,
          )
        end
      end

      if !fully_accepted && index == 0
        partialy_rejected = (
          diff_attribs.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } } ||
          diff_tags.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } }
        )

        rejected_version = ValidationResult.new(
          action: partialy_rejected ? 'reject' : nil,
          version: after['version'],
          diff_attribs:,
          diff_tags:,
        )
      end
    }

    [accepted_version, rejected_version].compact
  end

  sig {
    params(
    validators: T::Array[Validator],
  ).returns(T::Enumerable[[String, Integer, ValidationResult]])
  }
  def self.time_machine(validators)
    Enumerator.new { |yielder|
      ChangesDB.fetch_changes { |osm_change_object|
        validation_results = object_validation(validators, osm_change_object['p'])
        validation_results.each{ |validation_result|
          yielder << [osm_change_object['objtype'], osm_change_object['id'], validation_result]
        }
      }
    }
  end

  sig {
    params(
      validators: T::Array[Validator],
    ).void
  }
  def self.auto_validate(validators)
    actions = time_machine(validators).group_by { |_objtype, _id, validation_result|
      validation_result.action
    }

    # ret = [actions['accept'], actions[nil], actions['reject']]
    actions.each{ |action, validations|
      puts action
      validations.each{ |validation|
        puts validation.inspect
      }
    }
  end
end
