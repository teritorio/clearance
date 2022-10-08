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
  SELECT
      objtype,
      id,
      json_agg(row_to_json(t)::jsonb - 'objtype' - 'id')::jsonb AS p
  FROM (
      SELECT * FROM base_i
      UNION
      SELECT * FROM changes_i
  ) AS t
  GROUP BY
      objtype,
      id
  ORDER BY
      objtype,
      id
  "

    conn.exec(query) { |result|
      result.each(&block)
    }
  end


  sig { params(before: T.nilable(OSMObject), after: OSMObject).returns([HashActions, HashActions]) }
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


  sig { params(validators: T::Array[Validator]).void }
  def self.time_machine(validators)
    fetch_changes { |row|
      changes = T.cast(JSON.parse(row['p']).sort_by{ |change| change['version'] }, T::Array[OSMObject])

      before = T.let(nil, T.nilable(OSMObject))
      afters = T.let([], T::Array[OSMObject])
      if changes.size == 1
        afters = [changes[0]]
      elsif changes.size > 1
        before = changes[0]
        afters = changes[1..]
      end

      afters.reverse.each{ |after|
        diff_attribs, diff_tags = diff_osm_object(before, after)

        validators.each{ |validator|
          validator.apply(before, after, diff_attribs, diff_tags)
        }

        fully_accepted = (
          (diff_attribs.empty? || diff_attribs.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } }) &&
          (diff_tags.empty? || diff_tags.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } })
        )

        partialy_rejected = (
          diff_attribs.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } } ||
          diff_tags.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } }
        )

        # if fully_accepted
        #   # if partialy_rejected
        #   puts '=============='
        #   puts before.inspect
        #   puts '-'
        #   puts after.inspect
        #   puts diff_attribs.inspect
        #   puts diff_tags.inspect
        # end

        [fully_accepted, partialy_rejected]
      }
    }
  end
end
