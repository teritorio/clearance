# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_locha_sql'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class Duplicate < ValidatorLochaSql
    extend T::Sig

    sig {
      params(
        conn: T.nilable(PG::Connection),
        proj: Integer,
        prevalidation_clusters: T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]],
      ).void
    }
    def apply(conn, proj, prevalidation_clusters)
      # Get all way id from prevalidation_clusters
      # before_ids = T.let([], T::Array[Integer])
      after_node_ids = T.let([], T::Array[Integer])
      after_way_ids = T.let([], T::Array[Integer])
      prevalidation_clusters.collect{ |_accepted_links, conflations_matches|
        conflations_matches.collect{ |link|
          after = link.conflation.after
          if !after.nil?
            if after.objtype == 'n'
              after_node_ids << after.id
            elsif after.objtype == 'w'
              after_way_ids << after.id
            end
          end
        }
      }

      node_ids = T.let([], T::Array[T::Hash[String, T.untyped]])
      begin
        T.must(conn).transaction { |conn|
          specific_osm_tags_matches = T.must(@specific_osm_tags_matches)
          map_select = specific_osm_tags_matches.matches.each_with_index.to_h { |match, index|
            [index, [match.to_sql, match.duplicate_distance]]
          }

          map_select_index = map_select.collect{ |index, (sql, duplicate_distance)|
            "WHEN (#{sql}) THEN #{index}"
          }
          sql_map_select_index = "CASE #{sql_map_select_index} END"
          map_select_distance = map_select.collect{ |index, (sql, duplicate_distance)|
            "WHEN (#{sql}) THEN #{duplicate_distance}"
          }
          sql_osm_filter_tags = specific_osm_tags_matches.to_sql('postgres', '_', proc { |s| conn.escape_literal(s) })
          sql_map_select_distance = "CASE #{sql_map_select_distance} END"
          conn.exec(File.new('/sql/duplicate.sql').read
            .gsub(':osm_filter_tags', sql_osm_filter_tags)
            .gsub(':map_select_index', sql_map_select_index)
            .gsub(':map_select_distance', sql_map_select_distance)
            .gsub(':proj', proj.to_s)
            .gsub(':change_nodes_ids', "ARRAY[#{after_node_ids.join(',')}]")
            .gsub(':change_ways_ids', "ARRAY[#{after_way_ids.join(',')}]"))
          node_ids = T.cast(conn.exec('SELECT * FROM validator_network').to_a, T::Array[T::Hash[String, T.untyped]])
          raise 'rollback'
        }
      rescue StandardError => e
        raise unless e.message == 'rollback'
      end

      # Flag corresponding way that are disconnected or connected from the neighbor
      prevalidation_clusters.collect{ |_accepted_links, conflations_matches|
        conflations_matches.collect{ |link|
          next if link.conflation.before&.objtype != 'w'

          node_ids.collect{ |node_id|
            node_id['id'] == link.conflation.before&.id
          }.each{ |node_id|
            actions = link.result.diff.attribs['nodes'] || []
            actions << Validation::Action.new(
              validator_id: node_id['lost_connection'] ? 'lost_connection' : 'new_connection',
              action: 'reject',
              options: { 'node_id' => node_id['node_id'] },
            )
            link.result.diff.attribs['nodes'] = actions
          }
        }
      }
    end
  end
end
