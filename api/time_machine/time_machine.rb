# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/changes_db'
require './time_machine/validators/validator'
require './time_machine/types'


module TimeMachine
  extend T::Sig

  class DiffActions < T::Struct
    extend T::Sig

    const :attribs, Types::HashActions
    const :tags, Types::HashActions

    sig {
      returns(T::Boolean)
    }
    def fully_accepted?
      (attribs.empty? || attribs.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } }) &&
        (tags.empty? || tags.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } })
    end

    sig {
      returns(T::Boolean)
    }
    def partialy_rejected?
      attribs.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } } ||
        tags.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } }
    end
  end

  sig {
    params(
      before: T.nilable(ChangesDb::OSMChangeProperties),
      after: ChangesDb::OSMChangeProperties
    ).returns(DiffActions)
  }
  def self.diff_osm_object(before, after)
    diff_attribs = T.let({}, Types::HashActions)
    diff_tags = T.let({}, Types::HashActions)

    # Unchecked attribs
    # - version
    # - changeset
    # - uid
    # - username
    %w[lat lon nodes deleted members change_distance].each { |attrib|
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
    const :changeset_id, Integer
    const :created, String
    const :uid, Integer
    const :username, T.nilable(String)
    const :diff, DiffActions
  end

  sig {
    params(
      validators: T::Array[Validators::ValidatorBase],
      changes: T::Array[ChangesDb::OSMChangeProperties]
    ).returns(T::Array[ValidationResult])
  }
  def self.object_validation(validators, changes)
    before = T.let(nil, T.nilable(ChangesDb::OSMChangeProperties))
    afters = T.let([], T::Array[ChangesDb::OSMChangeProperties])
    if changes.size == 1
      afters = [T.must(changes[0])] # T.must useless here, but added to keep sorbet hapy
    elsif changes.size > 1
      before = changes[0]
      afters = T.must(changes[1..]) # T.must useless here, but added to keep sorbet hapy
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
            changeset_id: after['changeset_id'],
            created: after['created'],
            uid: after['uid'],
            username: after['username'],
            diff: diff,
          )
          break
        end
      end

      if !fully_accepted && index == 0
        partialy_rejected = diff.partialy_rejected?
        rejected_version = ValidationResult.new(
          action: partialy_rejected ? 'reject' : nil,
          version: after['version'],
          changeset_id: after['changeset_id'],
          created: after['created'],
          uid: after['uid'],
          username: after['username'],
          diff: diff,
        )
      end
    }

    [accepted_version, rejected_version].compact
  end

  sig {
    params(
      conn: PG::Connection,
      validators: T::Array[Validators::ValidatorBase],
    ).returns(T::Enumerable[[String, Integer, ValidationResult]])
  }
  def self.time_machine(conn, validators)
    Enumerator.new { |yielder|
      ChangesDb.fetch_changes(conn) { |osm_change_object|
        validation_results = object_validation(validators, osm_change_object['p'])
        validation_results.each{ |validation_result|
          yielder << [osm_change_object['objtype'], osm_change_object['id'], validation_result]
        }
      }
    }
  end

  sig {
    params(
      conn: PG::Connection,
      validators: T::Array[Validators::ValidatorBase],
    ).void
  }
  def self.validate(conn, validators)
    validations = time_machine(conn, validators)

    ChangesDb.apply_logs(conn, validations.collect{ |objtype, id, validation|
      ChangesDb::ValidationLog.new(
        objtype: objtype,
        id: id,
        version: validation.version,
        changeset_id: validation.changeset_id,
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
