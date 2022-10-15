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
    const :action, T.nilable(Types::ActionType)
    const :version, Integer
    const :created, String
    const :uid, Integer
    const :username, T.nilable(String)
    const :diff_attribs, Types::HashActions
    const :diff_tags, Types::HashActions
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
            created: after['created'],
            uid: after['uid'],
            username: after['username'],
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
          created: after['created'],
          uid: after['uid'],
          username: after['username'],
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
        diff_attribs: validation.diff_attribs,
        diff_tags: validation.diff_tags,
      )
    })
  end
end
