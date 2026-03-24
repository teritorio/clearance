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
          conn.exec(<<~SQL)
            CREATE TEMP TABLE validator_duplicate_config (
              key TEXT NOT NULL,
              value TEXT NOT NULL,
              distance INTEGER NOT NULL
            ) ON COMMIT DROP;
          SQL
          encoder = PG::BinaryEncoder::CopyRow.new
          conn.copy_data('COPY validator_duplicate_config (key, value, distance) FROM STDIN WITH (FORMAT binary)', encoder) do
            @settings.config.each { |key, values|
              values.each { |value, distance|
                conn.put_copy_data([key, value, distance])
              }
            }
          end

          sql_osm_filter_tags = @settings.osm_tags_matches.to_sql('postgres', '_', proc { |s| conn.escape_literal(s) })
          conn.exec(File.new('/sql/duplicate.sql').read
            .gsub(':osm_filter_tags', sql_osm_filter_tags)
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
