# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_locha'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class Network < ValidatorLocha
    extend T::Sig

    sig {
      params(
        conn: T.nilable(PG::Connection),
        _proj: Integer,
        prevalidation_clusters: T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]],
      ).void
    }
    def apply(conn, _proj, prevalidation_clusters)
      # Get all way id from prevalidation_clusters
      before_ids = T.let([], T::Array[Integer])
      after_ids = T.let([], T::Array[Integer])
      prevalidation_clusters.collect{ |_accepted_links, conflations_matches|
        conflations_matches.collect{ |link|
          if link.conflation.before&.objtype == 'w'
            before_ids << T.must(link.conflation.before&.id)
          end
          if link.conflation.after&.objtype == 'w'
            after_ids << T.must(link.conflation.after&.id)
          end
        }
      }

      # Get node_id that are in change but not in base, and node_id that are in base but not in change
      node_ids = T.let([], T::Array[T::Hash[String, T.untyped]])
      begin
        T.must(conn).transaction { |conn|
          sql_osm_filter_tags = @osm_tags_matches.to_sql('postgres', '_', proc { |s| conn.escape_literal(s) })
          conn.exec(File.new('/sql/network.sql').read
            .gsub(':osm_filter_tags', sql_osm_filter_tags)
            .gsub(':base_ways_ids', "ARRAY[#{before_ids.join(',')}]")
            .gsub(':change_ways_ids', "ARRAY[#{after_ids.join(',')}]"))
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
