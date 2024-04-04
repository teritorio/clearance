# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/types'
require './lib/time_machine/osm/tags_matches'
require 'overpass_parser/visitor'

module Db
  extend T::Sig

  class OverpassCenterResult < T::InexactStruct
    const :lon, Float
    const :lat, Float
  end

  class OverpassResult < Osm::ObjectId
    const :timestamp, String
    const :tags, Osm::OsmTags
    const :lon, T.nilable(Float)
    const :lat, T.nilable(Float)
    const :center, T.nilable(OverpassCenterResult)
  end

  class Overpass
    extend T::Sig

    sig {
      params(
        conn: PG::Connection,
        query: String,
      ).returns(T::Array[T::Hash[Symbol, OverpassResult]])
    }
    def self.query(conn, query)
      request = OverpassParser.tree(query)[0]
      sql = File.new('/sql/overpasslike.sql').read
      sql += request.to_sql(->(s) { conn.escape_literal(s) }).gsub('ST_PointOnSurface(geom) AS geom', 'ST_X(ST_PointOnSurface(geom)) AS lon, ST_Y(ST_PointOnSurface(geom)) AS lat')

      conn.exec(sql) { |result|
        result.collect{ |row|
          ret = {
            id: row['id'],
            version: row['version'],
            timestamp: row['created'],
            tags: row['tags'],
          }
          if row['osm_type'] == 'n'
            ret.update({
              type: 'node',
              lat: T.must(row['lat']),
              lon: T.must(row['lon']),
            })
          else
            ret.update({
              type: row['osm_type'] == 'w' ? 'way' : 'relation',
              center: {
                lat: T.must(row['lat']),
                lon: T.must(row['lon']),
              },
            })
          end
        }
      }
    end
  end
end
