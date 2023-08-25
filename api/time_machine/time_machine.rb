# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/changes_db'
require './time_machine/changeset'
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
    # - nodes
    # - lat
    # - lon
    # - geom_distance
    %w[deleted members geom_distance].each { |attrib|
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
    const :deleted, T::Boolean
    prop :changeset_ids, T::Array[Integer]
    const :created, String
    const :diff, DiffActions
  end

  sig {
    params(
      config: Configuration::Config,
      changes: T::Array[ChangesDb::OSMChangeProperties]
    ).returns(T::Array[ValidationResult])
  }
  def self.object_validation(config, changes)
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
    rejected_changeset_ids = []

    fully_accepted = T.let(false, T::Boolean)
    afters.reverse.each_with_index{ |after, index|
      diff = diff_osm_object(before, after)

      config.validators.each{ |validator|
        validator.apply(before, after, diff)
      }
      if !diff.attribs['geom_distance'].nil?
        diff.attribs['geom'] = (diff.attribs['geom'] || []) + T.must(diff.attribs['geom_distance'])
        diff.attribs.delete('geom_distance')
      end

      fully_accepted = diff.fully_accepted?
      if fully_accepted
        accepted_version = ValidationResult.new(
          action: 'accept',
          version: after['version'],
          deleted: after['deleted'],
          changeset_ids: T.must(afters.reverse[index..]&.collect{ |version| version['changeset_id'] }),
          created: after['created'],
          diff: diff,
        )
        break
      elsif index == 0
        partialy_rejected = diff.partialy_rejected?
        rejected_version = ValidationResult.new(
          action: partialy_rejected ? 'reject' : nil,
          version: after['version'],
          deleted: after['deleted'],
          changeset_ids: [after['changeset_id']],
          created: after['created'],
          diff: diff,
        )
      else
        rejected_changeset_ids << after['changeset_id']
      end
    }

    if !rejected_version.nil?
      rejected_version.changeset_ids += rejected_changeset_ids
    end

    [accepted_version, rejected_version].compact
  end

  sig {
    params(
      conn: PG::Connection,
      config: Configuration::Config,
    ).returns(T::Enumerable[[String, Integer, T::Array[String], ValidationResult]])
  }
  def self.time_machine(conn, config)
    Enumerator.new { |yielder|
      ChangesDb.fetch_changes(conn) { |osm_change_object|
        matches = [osm_change_object['p'][0], osm_change_object['p'][-1]].compact.uniq.collect{ |object|
          config.osm_tags_matches.match(object['tags'])
        }.flatten(1).collect{ |_tag, match|
          ChangesDb::ValidationLogMatch.new(
            sources: match.sources&.compact || [],
            selector: match.selector,
            user_groups: match.user_groups,
          )
        }.flatten(1).uniq

        validation_results = object_validation(config, osm_change_object['p'])
        validation_results.each{ |validation_result|
          yielder << [osm_change_object['objtype'], osm_change_object['id'], matches, validation_result]
        }
      }
    }
  end

  sig {
    params(
      conn: PG::Connection,
      config: Configuration::Config,
    ).void
  }
  def self.validate(conn, config)
    validations = time_machine(conn, config)

    ChangesDb.apply_logs(conn, validations.collect{ |objtype, id, matches, validation|
      ChangesDb::ValidationLog.new(
        objtype: objtype,
        id: id,
        version: validation.version,
        deleted: validation.deleted,
        changeset_ids: validation.changeset_ids,
        created: validation.created,
        matches: matches,
        action: validation.action,
        validator_uid: nil,
        diff_attribs: validation.diff.attribs,
        diff_tags: validation.diff.tags,
      )
    })
  end
end
