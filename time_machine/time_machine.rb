# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'pg'
require 'json'
require './validators'
require 'yaml'
require 'ostruct'
require './types'


module TimeMachine
  include Validators
  include Types
  extend T::Sig

  sig { params(block: T.proc.params(arg0: T::Hash[String, T.untyped]).void).void }
  def self.fetch_changes(&block)
    conn = PG::Connection.new('postgresql://postgres@postgres:5432/postgres')

    query = "
WITH base_i AS (
  SELECT
      base.objtype,
      base.id,
      base.version,
      false AS deleted,
      base.changeset_id,
      base.created,
      base.uid,
      base.username,
      base.tags,
      base.lon,
      base.lat,
      base.nodes,
      base.members
  FROM
      osm_base AS base
      JOIN osm_changes AS changes ON
          changes.objtype = base.objtype AND
          changes.id = base.id
)
SELECT
    objtype,
    id,
    json_agg(row_to_json(t)::jsonb - 'objtype' - 'id')::jsonb AS p
FROM (
    SELECT * FROM base_i
    UNION
    SELECT * FROM osm_changes
) AS t
GROUP BY
    objtype,
    id
ORDER BY
    objtype,
    id
  "

    conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn)
    conn.exec(query) { |result|
      result.each(&block)
    }
  end


  sig { params(before: T.nilable(OSMChangeProperties), after: OSMChangeProperties).returns([HashActions, HashActions]) }
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
      changes: T::Array[OSMChangeProperties]
    ).returns(T::Array[ValidationResult])
  }
  def self.object_validation(validators, changes)
    before = T.let(nil, T.nilable(OSMChangeProperties))
    afters = T.let([], T::Array[OSMChangeProperties])
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
      fetch_changes { |row|
        osm_change_object = T.cast(row, OSMChangeObject)
        validation_results = object_validation(validators, osm_change_object['p'])
        validation_results.each{ |validation_result|
          yielder << [row['objtype'], row['id'], validation_result]
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
