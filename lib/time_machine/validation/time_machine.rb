# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/changes_db'
require './lib/time_machine/validation/lo_cha'
require './lib/time_machine/validation/diff_actions'
require './lib/time_machine/validators/validator'
require './lib/time_machine/validation/types'


module Validation
  extend T::Sig

  class ValidationResult < T::Struct
    const :action, T.nilable(ActionType)
    const :before_object, T.nilable(Osm::ObjectChangeId)
    const :after_object, Osm::ObjectChangeId
    const :sementic_deletetion, T::Boolean
    prop :changeset_ids, T.nilable(T::Array[Integer])
    const :created, String
    const :diff, DiffActions
  end

  sig {
    params(
      validators: T::Array[Validators::ValidatorBase],
      before: T.nilable(OSMChangeProperties),
      before_at_now: T.nilable(OSMChangeProperties),
      after: T.nilable(OSMChangeProperties),
    ).returns(ValidationResult)
  }
  def self.object_validation(validators, before, before_at_now, after)
    throw 'Precondition fails' if before.nil? && after.nil?

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
      before_object: before.nil? ? nil : Osm::ObjectChangeId.new(objtype: before['objtype'], id: before['id'], version: before['version'], deleted: before['deleted']),
      after_object: T.must(after.nil? ?
        before_at_now.nil? ? nil : Osm::ObjectChangeId.new(objtype: before_at_now['objtype'], id: before_at_now['id'], version: before_at_now['version'], deleted: before_at_now['deleted']) :
        Osm::ObjectChangeId.new(objtype: after['objtype'], id: after['id'], version: after['version'], deleted: after['deleted'])),
      sementic_deletetion: after.nil?,
      changeset_ids: T.must(after || before_at_now)['changesets']&.pluck('id'),
      created: T.must(after || before_at_now)['created'],
      diff: diff,
    )
  end

  sig {
    params(
      conn: PG::Connection,
      config: Configuration::Config,
    ).returns(T::Enumerable[[Integer, T::Array[ValidationLogMatch], ValidationResult]])
  }
  def self.time_machine(conn, config)
    accept_all_validators = [Validators::All.new(id: 'no_matching_user_groups', osm_tags_matches: Osm::TagsMatches.new([]), action: 'accept')]
    Enumerator.new { |yielder|
      fetch_changes(conn, config.local_srid, config.locha_cluster_distance, config.user_groups) { |lo_cha|
        befores = lo_cha.collect(&:first).compact
        afters = lo_cha.collect(&:last).compact
        conflations = LoCha.conflate(befores, afters, config.local_srid, 200.0)

        conflations.each{ |conflation|
          matches = [conflation[0], conflation[-1]].compact.collect{ |object|
            config.osm_tags_matches.match(object['tags'])
          }.flatten(1).uniq.collect{ |overpass, match|
            ValidationLogMatch.new(
              sources: match.sources&.compact || [],
              selectors: [overpass],
              user_groups: match.user_groups.intersection(conflation.compact.pluck('group_ids').flatten.uniq),
              name: match.name,
              icon: match.icon,
            )
          }.flatten(1).uniq

          matching_group = matches.any?{ |match|
            !match.user_groups&.empty?
          }
          validators = matching_group ? config.validators : accept_all_validators
          before, before_at_now, after = conflation
          validation_result = object_validation(validators, before, before_at_now, after)
          yielder << [
            T.must(before || after)['locha_id'],
            matches,
            validation_result
          ]
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

    apply_logs(conn, validations.collect{ |locha_id, matches, validation|
      ValidationLog.new(
        locha_id: locha_id,
        before_objects: validation.before_object,
        after_objects: validation.after_object,
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
