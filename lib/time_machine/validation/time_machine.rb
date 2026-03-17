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
    prop :action, T.nilable(ActionType)
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
      prevalidation_clusters: T::Array[[T::Array[Link], T::Array[Link]]],
    ).returns(T::Array[[T::Array[Link], T::Array[Link]]])
  }
  def self.time_machine_validate(validators, prevalidation_clusters)
    prevalidation_clusters.collect{ |accepted_links, conflations_matches|
      conflations_matches.each{ |link|
        validators.each{ |validator|
          validator.apply(link.conflation.before, link.conflation.after, link.result.diff)
        }
      }

      conflations_matches.collect{ |link|
        if !link.result.diff.attribs['geom_distance'].nil?
          link.result.diff.attribs['geom'] = (link.result.diff.attribs['geom'] || []) + T.must(link.result.diff.attribs['geom_distance'])
          link.result.diff.attribs.delete('geom_distance')
        end

        link.result.action = link.result.diff.fully_accepted? ? 'accept' : link.result.diff.partialy_rejected? ? 'reject' : nil
      }

      [accepted_links, conflations_matches]
    }
  end

  sig {
    params(
      config: Configuration::Config,
      locha_id: Integer,
      lo_cha: T::Array[[T.nilable(OSMChangeProperties), OSMChangeProperties]],
    ).returns(LoCha)
  }
  def self.time_machine_locha(config, locha_id, lo_cha)
    conflation_clusters = OSMLogicalHistory::Conflation[OSMChangeProperties].new.conflate_cluster(
      lo_cha.collect(&:first).compact,
      lo_cha.collect(&:last).compact,
      200.0
    )

    prevalidation_clusters = conflation_clusters.collect{ |conflations|
      remeaning_conflations = T.let([], T::Array[Link])
      links = T.let([], T::Array[Link])
      conflations.each{ |conflation|
        throw 'Precondition fails' if conflation.before.nil? && conflation.after.nil?
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

        link = Link.new(
          conflation: conflation,
          validations: matches,
          result: ValidationResult.new(
            action: 'accept',
            changeset_ids: T.must(conflation.after || conflation.before_at_now).changesets&.pluck('id'),
            created: T.must(conflation.after || conflation.before_at_now).created,
            diff: matching_group ? diff_osm_object(conflation.before, conflation.after) : DiffActions.new(attribs: {}, tags: {}),
          ),
        )
        if matching_group
          remeaning_conflations << link
        else
          links << link
        end
      }
      [links, remeaning_conflations]
    }

    prevalidation_clusters = time_machine_validate(config.validators, prevalidation_clusters)

    locha_action = T.let('accept', T.nilable(String))
    semantic_clusters = prevalidation_clusters.collect{ |links, validation_results|
      cluster_action = T.let('accept', T.nilable(String))
      validation_results.each{ |link|
        if link.result.action == 'reject'
          cluster_action = 'reject'
          break
        elsif link.result.action.nil?
          cluster_action = nil
        end
      }

      if cluster_action == 'reject'
        validation_results = (links + validation_results).collect{ |link|
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
        links = [] # already merged above
      end

      if cluster_action == 'reject'
        locha_action = 'reject'
      elsif locha_action != 'reject' && cluster_action.nil?
        locha_action = nil
      end
      SemanticCluster.new(
        action: cluster_action,
        links: links + validation_results,
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
    Enumerator.new { |yielder|
      index = 0
      objects = 0
      fetch_changes(conn, config.local_srid, config.locha_cluster_distance, config.user_groups) { |locha_id, lo_cha|
        index += 1
        objects += lo_cha.size
        if index % 100 == 0
          puts "  Processing locha ##{index}, objects processed: #{objects}..."
        end
        yielder << time_machine_locha(config, locha_id, lo_cha)
      }
      puts "  Finished processing #{index} locha, total objects processed: #{objects}."
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
      locha.semantic_clusters.each_with_index.collect{ |cluster, semantic_group_index|
        cluster.links.collect{ |link|
          ValidationLog.new(
            locha_id: locha.locha_id,
            semantic_group: ((locha.locha_id + semantic_group_index) + 2**31) % 2**32 - 2**31,
            before_objects: (Osm::ObjectChangeId.from_hash(link.conflation.before.to_h) if !link.conflation.before.nil?),
            after_objects: (Osm::ObjectChangeId.from_hash(link.conflation.after.to_h) if !link.conflation.after.nil?),
            changeset_ids: link.result.changeset_ids,
            created: link.result.created,
            conflation: link.conflation,
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
