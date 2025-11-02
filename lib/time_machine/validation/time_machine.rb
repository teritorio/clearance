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
    prop :changeset_ids, T.nilable(T::Array[Integer])
    const :created, String
    const :diff, DiffActions
    const :action, T.nilable(ActionType)
  end

  class Link < T::Struct
    const :conflation, OSMLogicalHistory::Conflation::ConflationNilableOnly[OSMChangeProperties]
    const :validations, T::Array[ValidationLogMatch]
    const :result, ValidationResult
  end

  class SemanticCluster < T::Struct
    const :links, T::Array[Link]
    const :action, T.nilable(ActionType)
  end

  class LoCha < T::Struct
    const :locha_id, Integer
    const :semantic_clusters, T::Array[SemanticCluster]
    const :action, T.nilable(ActionType)
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
      changeset_ids: T.must(after || before_at_now).changesets&.pluck('id'),
      created: T.must(after || before_at_now).created,
      diff: diff,
    )
  end

  sig {
    params(
      config: Configuration::Config,
      locha_id: Integer,
      lo_cha: T::Array[[T.nilable(OSMChangeProperties), OSMChangeProperties]],
      accept_all_validators: T::Array[Validators::ValidatorBase],
    ).returns(LoCha)
  }
  def self.time_machine_locha(config, locha_id, lo_cha, accept_all_validators)
    befores = lo_cha.collect(&:first).compact
    afters = lo_cha.collect(&:last).compact
    conflation_clusters = OSMLogicalHistory::Conflation[OSMChangeProperties].new.conflate_cluster(befores, afters, 200.0)

    locha_action = T.let('accept', T.nilable(String))
    semantic_clusters = conflation_clusters.collect{ |conflations|
      cluster_action = T.let('accept', T.nilable(String))
      validation_results = conflations.collect{ |conflation|
        matches = [conflation.before, conflation.after].compact.collect{ |object|
          config.osm_tags_matches.match(object.tags)
        }.flatten(1).uniq.collect{ |overpass, match|
          ValidationLogMatch.new(
            sources: match.sources&.compact || [],
            selectors: [overpass],
            user_groups: match.user_groups.intersection(conflation.to_a.compact.collect(&:group_ids).flatten.uniq),
            name: match.name,
            icon: match.icon,
          )
        }.flatten(1).uniq

        matching_group = matches.any?{ |match|
          !match.user_groups&.empty?
        }
        validators = matching_group ? config.validators : accept_all_validators
        validation = object_validation(validators, conflation.before, conflation.before_at_now, conflation.after)
        if validation.action == 'reject'
          cluster_action = 'reject'
        elsif cluster_action != 'reject' && validation.action.nil?
          cluster_action = nil
        end
        Link.new(
          conflation: conflation,
          validations: matches,
          result: validation,
        )
      }

      if cluster_action == 'reject'
        validation_results = validation_results.collect{ |link|
          next(link) if link.result.action == 'reject'

          validation = link.result.with(action: 'reject')
          diff_action = Validation::Action.new(validator_id: 'semantic_rejection_propagation', action: 'reject')
          validation.diff.attribs['id'] = (validation.diff.attribs['id'] || []) + [diff_action]
          Link.new(
            conflation: link.conflation,
            validations: link.validations,
            result: validation
          )
        }
      end

      if cluster_action == 'reject'
        locha_action = 'reject'
      elsif locha_action != 'reject' && cluster_action.nil?
        locha_action = nil
      end
      SemanticCluster.new(
        action: cluster_action,
        links: validation_results,
      )
    }

    LoCha.new(
      locha_id: locha_id,
      action: locha_action,
      semantic_clusters: semantic_clusters,
    )
  end

  sig {
    params(
      conn: PG::Connection,
      config: Configuration::Config,
    ).returns(T::Enumerable[LoCha])
  }
  def self.time_machine(conn, config)
    accept_all_validators = [Validators::All.new(id: 'no_matching_user_groups', osm_tags_matches: Osm::TagsMatches.new([]), action: 'accept')]
    Enumerator.new { |yielder|
      fetch_changes(conn, config.local_srid, config.locha_cluster_distance, config.user_groups) { |locha_id, lo_cha|
        yielder << time_machine_locha(config, locha_id, lo_cha, accept_all_validators)
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

    apply_logs(conn, validations.collect{ |locha|
      locha.semantic_clusters.collect{ |cluster|
        cluster.links.collect{ |link|
          ValidationLog.new(
            locha_id: locha.locha_id,
            before_objects: (Osm::ObjectChangeId.from_hash(link.conflation.before.to_h) if !link.conflation.before.nil?),
            after_objects: (Osm::ObjectChangeId.from_hash(link.conflation.after.to_h) if !link.conflation.after.nil?),
            changeset_ids: link.result.changeset_ids,
            created: link.result.created,
            matches: link.validations,
            action: link.result.action,
            validator_uid: nil,
            diff_attribs: link.result.diff.attribs,
            diff_tags: link.result.diff.tags,
          )
        }
      }
    }.flatten)
  end
end
