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
        conn.exec(File.read(File.join(File.dirname(__FILE__), 'network.sql'))
          .gsub(':osm_filter_tags', sql_osm_filter_tags))
      }
    end

    Neighbor = T.type_alias {
      { 'x' => Float, 'y' => Float, 'id' => Integer, 'way_id' => Integer }
    }

    sig {
      params(
        conflations_matches: T::Array[Validation::Link],
        neighbors_index: T::Hash[Integer, { 'base_neighbors' => T::Array[Neighbor], 'change_neighbors' => T::Array[Neighbor] }],
      ).returns([T::Hash[Integer, T::Array[Neighbor]], T::Hash[Integer, T::Array[Neighbor]]])
    }
    def neighbors(conflations_matches, neighbors_index)
      before_ids = T.let([], T::Array[Integer])
      after_ids = T.let([], T::Array[Integer])
      conflations_matches.each{ |link|
        before_ids << T.must(link.conflation.before&.id)
        after_ids << T.must(link.conflation.after&.id) if link.conflation.after&.deleted == false
      }
      before_ids = before_ids.uniq
      after_ids = after_ids.uniq

      before_neighbors = before_ids.index_with{ |before_id|
        T.cast(neighbors_index.dig(before_id, 'base_neighbors') || [], T::Array[Neighbor])
      }
      after_neighbors = after_ids.index_with{ |after_id|
        T.cast(neighbors_index.dig(after_id, 'change_neighbors') || [], T::Array[Neighbor])
      }

      [before_neighbors, after_neighbors]
    end

    sig {
      params(
        all_before_neighbors: T::Array[Neighbor],
        all_after_neighbors: T::Array[Neighbor],
      ).returns([T::Array[Neighbor], T::Array[Neighbor]])
    }
    def symmetric_difference(all_before_neighbors, all_after_neighbors)
      only_all_before_neighbors = all_before_neighbors.select{ |neighbor| !all_after_neighbors.any?{ |n| n['id'] == neighbor['id'] || n['way_id'] == neighbor['way_id'] || (n['x'] == neighbor['x'] && n['y'] == neighbor['y']) } }
      only_all_after_neighbors = all_after_neighbors.select{ |neighbor| !all_before_neighbors.any?{ |n| n['id'] == neighbor['id'] || n['way_id'] == neighbor['way_id'] || (n['x'] == neighbor['x'] && n['y'] == neighbor['y']) } }

      [only_all_before_neighbors, only_all_after_neighbors]
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
      neighbors_ways = T.cast(conn.exec('SELECT * FROM validator_network WHERE locha_id = $1', T.unsafe([locha_id])).to_a, T::Array[{ 'id' => Integer, 'base_neighbors' => T::Array[Neighbor], 'change_neighbors' => T::Array[Neighbor] }])
      neighbors_index = neighbors_ways.index_by { |row| row['id'] }

      # Flag corresponding way that are disconnected or connected from the neighbor
      prevalidation_clusters.collect{ |_accepted_links, conflations_matches|
        conflations_matches = conflations_matches.select{ |link|
          link.conflation.before&.objtype == 'w' && link.conflation.after&.objtype == 'w'
        }

        before_neighbors, after_neighbors = neighbors(conflations_matches, neighbors_index)

        all_before_neighbors = before_neighbors.values.flatten.uniq
        all_after_neighbors = after_neighbors.values.flatten.uniq

        # Symmetric difference of before_neighbors and after_neighbors to find disconnected and connected neighbors
        only_all_before_neighbors, only_all_after_neighbors = symmetric_difference(all_before_neighbors, all_after_neighbors)

        only_before_neighbors = before_neighbors.transform_values{ |neighbors| neighbors & only_all_before_neighbors }.compact_blank
        only_after_neighbors = after_neighbors.transform_values{ |neighbors| neighbors & only_all_after_neighbors }.compact_blank

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
          only_neighbors.each{ |before_id, neighbors|
            link = T.must(conflations_matches_index[before_id])
            actions = link.result.diff.attribs['geom'] || []
            actions << Validation::Action.new(
              validator_id: validator_id,
              action: 'reject',
              options: { option_key => neighbors },
            )
            link.result.diff.attribs['geom'] = actions
          }
        }
      }
    end
  end
end
