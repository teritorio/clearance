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

  class DiffActions < T::Struct
    const :attribs, Types::HashActions
    const :tags, Types::HashActions

    def fully_accepted?
      (attribs.empty? || attribs.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } }) &&
        (tags.empty? || tags.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } })
    end

    def partialy_rejected?
      attribs.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } } ||
        tags.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } }
    end
  end

  sig {
    params(
      before: T.nilable(ChangesDB::OSMChangeProperties),
      after: ChangesDB::OSMChangeProperties
    ).returns(DiffActions)
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

    DiffActions.new(attribs: diff_attribs, tags: diff_tags)
  end

  class ValidationResult < T::Struct
    const :action, T.nilable(Types::ActionType)
    const :version, Integer
    const :created, String
    const :uid, Integer
    const :username, T.nilable(String)
    const :diff, DiffActions
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

    fully_accepted = T.let(false, T::Boolean)
    afters.reverse.each_with_index{ |after, index|
      diff = diff_osm_object(before, after)

      validators.each{ |validator|
        validator.apply(before, after, diff)
      }

      if !accepted_version
        fully_accepted = diff.fully_accepted?
        if fully_accepted
          accepted_version = ValidationResult.new(
            action: 'accept',
            version: after['version'],
            created: after['created'],
            uid: after['uid'],
            username: after['username'],
            diff:,
          )
          break
        end
      end

      if !fully_accepted && index == 0
        partialy_rejected = diff.partialy_rejected?
        rejected_version = ValidationResult.new(
          action: partialy_rejected ? 'reject' : nil,
          version: after['version'],
          created: after['created'],
          uid: after['uid'],
          username: after['username'],
          diff:,
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
  def self.validate(validators)
    validations = time_machine(validators)

    ChangesDB.apply_logs(validations.collect{ |objtype, id, validation|
      ChangesDB::ValidationLog.new(
        objtype:,
        id:,
        version: validation.version,
        created: validation.created,
        uid: validation.uid,
        username: validation.username,
        action: validation.action,
        validator_uid: nil,
        diff_attribs: validation.diff.attribs,
        diff_tags: validation.diff.tags,
      )
    })
  end
end
