# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_locha_sql'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class Network < ValidatorLochaSql
    extend T::Sig

    sig {
      params(
        conn: T.nilable(PG::Connection),
        _proj: Integer,
      ).void
    }
    def pre_compute_sql(conn, _proj)
      T.must(conn).transaction { |conn|
        specific_osm_tags_matches = T.must(@settings.specific_osm_tags_matches)
        sql_osm_filter_tags = specific_osm_tags_matches.to_sql('postgres', '_', proc { |s| conn.escape_literal(s) })
        conn.exec(File.new(File.join(File.dirname(__FILE__), 'network.sql')).read
          .gsub(':osm_filter_tags', sql_osm_filter_tags))
      }
    end

    sig {
      params(
        conflations_matches: T::Array[Validation::Link],
        neighbors_ways_index: T::Hash[Integer, { 'base_neighbors_ways' => T::Array[Integer], 'change_neighbors_ways' => T::Array[Integer] }],
      ).returns([T::Hash[Integer, T::Array[Integer]], T::Hash[Integer, T::Array[Integer]]])
    }
    def neighbors(conflations_matches, neighbors_ways_index)
      before_ids = T.let([], T::Array[Integer])
      after_ids = T.let([], T::Array[Integer])
      conflations_matches.each{ |link|
        before_ids << T.must(link.conflation.before&.id)
        after_ids << T.must(link.conflation.after&.id) if link.conflation.after&.deleted == false
      }
      before_ids = before_ids.uniq
      after_ids = after_ids.uniq

      before_neighbors = before_ids.collect{ |before_id|
        T.cast(neighbors_ways_index.dig(before_id, 'base_neighbors_ways') || [], T::Array[Integer]).collect{ |n| [n, before_id] }
      }.flatten(1).group_by(&:first).transform_values{ |v| v.collect(&:last).uniq }
      after_neighbors = after_ids.collect{ |after_id|
        T.cast(neighbors_ways_index.dig(after_id, 'change_neighbors_ways') || [], T::Array[Integer]).collect{ |n| [n, after_id] }
      }.flatten(1).group_by(&:first).transform_values{ |v| v.collect(&:last).uniq }

      [before_neighbors, after_neighbors]
    end

    sig {
      params(
        conn: T.nilable(PG::Connection),
        locha_id: Integer,
        prevalidation_clusters: T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]],
      ).void
    }
    def apply(conn, locha_id, prevalidation_clusters)
      # Get node_id that are in change but not in base, and node_id that are in base but not in change
      neighbors_ways = T.cast(conn.exec('SELECT * FROM validator_network WHERE locha_id = $1', T.unsafe([locha_id])).to_a, T::Array[{ 'id' => Integer, 'base_neighbors_ways' => T::Array[Integer], 'change_neighbors_ways' => T::Array[Integer] }])
      neighbors_ways_index = neighbors_ways.index_by { |row| row['id'] }

      # Flag corresponding way that are disconnected or connected from the neighbor
      prevalidation_clusters.collect{ |_accepted_links, conflations_matches|
        conflations_matches = conflations_matches.select{ |link|
          link.conflation.before&.objtype == 'w' && link.conflation.after&.objtype == 'w'
        }

        before_neighbors, after_neighbors = neighbors(conflations_matches, neighbors_ways_index)

        # Symmetric difference of before_neighbors and after_neighbors to find disconnected and connected neighbors
        only_before_neighbors = before_neighbors.select{ |key, _| !after_neighbors.key?(key) }
        only_after_neighbors = after_neighbors.select{ |key, _| !before_neighbors.key?(key) }

        conflations_matches_before_index = conflations_matches.index_by{ |link| link.conflation.before&.id }
        conflations_matches_after_index = conflations_matches.index_by{ |link| link.conflation.after&.id }
        a = T.let({
          only_before_neighbors => [conflations_matches_before_index, 'lost_connection', 'disconnected_from_way_id'],
          only_after_neighbors => [conflations_matches_after_index, 'gain_connection', 'connected_to_way_id'],
        }, T::Hash[
          T::Hash[Integer, T::Array[Integer]],
          [T::Hash[Integer, Validation::Link], String, String]
        ])
        a.each{ |only_neighbors, (conflations_matches_index, validator_id, option_key)|
          only_neighbors.each{ |neighbor, before_ids|
            before_ids.each{ |before_id|
              link = T.must(conflations_matches_index[before_id])
              actions = link.result.diff.attribs['geom'] || []
              actions << Validation::Action.new(
                validator_id: validator_id,
                action: 'reject',
                options: { option_key => neighbor },
              )
              link.result.diff.attribs['geom'] = actions
            }
          }
        }
      }
    end
  end
end
