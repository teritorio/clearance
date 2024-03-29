# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/changes_db'
require './lib/time_machine/validation/diff_actions'
require './lib/time_machine/validators/validator'
require './lib/time_machine/validation/types'


module Validation
  extend T::Sig

  class ValidationResult < T::Struct
    const :action, T.nilable(ActionType)
    const :version, Integer
    const :deleted, T::Boolean
    prop :changeset_ids, T::Array[Integer]
    const :created, String
    const :diff, DiffActions
  end

  sig {
    params(
      validators: T::Array[Validators::ValidatorBase],
      changes: T::Array[OSMChangeProperties]
    ).returns(ValidationResult)
  }
  def self.object_validation(validators, changes)
    before = T.must(changes[0])['is_change'] ? nil : T.let(T.must(changes[0]), OSMChangeProperties)
    after = T.let(T.must(changes[-1]), OSMChangeProperties)

    diff = diff_osm_object(before, after)
    validators.each{ |validator|
      validator.apply(before, after, diff)
    }
    if !diff.attribs['geom_distance'].nil?
      diff.attribs['geom'] = (diff.attribs['geom'] || []) + T.must(diff.attribs['geom_distance'])
      diff.attribs.delete('geom_distance')
    end

    ValidationResult.new(
      action: diff.fully_accepted? ? 'accept' : diff.partialy_rejected? ? 'reject' : nil,
      version: after['version'],
      deleted: after['deleted'],
      changeset_ids: after['changesets'].pluck('id'),
      created: after['created'],
      diff: diff,
    )
  end

  sig {
    params(
      conn: PG::Connection,
      config: Configuration::Config,
    ).returns(T::Enumerable[[String, Integer, T::Array[String], ValidationResult]])
  }
  def self.time_machine(conn, config)
    accept_all_validators = [Validators::All.new(id: 'no_matching_user_groups', osm_tags_matches: Osm::TagsMatches.new([]), action: 'accept')]
    Enumerator.new { |yielder|
      fetch_changes(conn, config.user_groups) { |osm_change_object|
        osm_change_object_p = [osm_change_object['p'][0], osm_change_object['p'][-1]].compact.uniq
        matches = osm_change_object_p.collect{ |object|
          config.osm_tags_matches.match(object['tags'])
        }.flatten(1).uniq.collect{ |overpass, match|
          ValidationLogMatch.new(
            sources: match.sources&.compact || [],
            selectors: [overpass],
            user_groups: match.user_groups.intersection(osm_change_object_p.pluck('group_ids').flatten.uniq),
            name: match.name,
            icon: match.icon,
          )
        }.flatten(1).uniq

        matching_group = matches.any?{ |match|
          !match.user_groups&.empty?
        }
        validators = matching_group ? config.validators : accept_all_validators
        validation_result = object_validation(validators, osm_change_object['p'])
        yielder << [osm_change_object['objtype'], osm_change_object['id'], matches, validation_result]
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

    apply_logs(conn, validations.collect{ |objtype, id, matches, validation|
      ValidationLog.new(
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
