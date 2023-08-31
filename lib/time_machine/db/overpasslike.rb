# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/types'

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
        query: String,
      ).returns(T::Array[[String, T.nilable(Integer)]])
    }
    def self.parse(query)
      # Crud overpass extraction of tag selector of nwr line like
      # nrw[amenity=drinking_water][name](area.a);

      area = /area\(([0-9]+)\)/.match(query)&.[](1)
      area_id = area.nil? ? nil : area.to_i - 3_600_000_000

      query.split(';').select{ |line|
        line.strip.start_with?('nwr')
      }.map{ |nwr|
        nwr[(nwr.index('['))..(nwr.rindex(']'))]
      }.compact.collect{ |selector|
        [selector, area_id]
      }
    end

    sig {
      params(
        conn: PG::Connection,
        query: String,
      ).returns(T::Array[T::Hash[Symbol, OverpassResult]])
    }
    def self.query(conn, query)
      parse(query).collect{ |selector, area_id|
        db_query(conn, selector, area_id)
      }.flatten(1).uniq
    end

    sig {
      params(
        conn: PG::Connection,
        tags: String,
        area_id: T.nilable(Integer),
      ).returns(T::Array[T::Hash[Symbol, OverpassResult]])
    }
    def self.db_query(conn, tags, area_id)
      sql_osm_filter_tags = Osm::TagsMatch.new(tags).to_sql(->(s) { conn.escape_literal(s) })
      sql = File.new('/sql/overpasslike.sql').read
                .gsub(':osm_filter_tags', sql_osm_filter_tags)
                .gsub(':area_id', conn.escape_literal(area_id.to_s))
      conn.exec(sql) { |result|
        result.collect{ |row|
          object = T.let(OverpassResult.from_hash(row), OverpassResult)

          ret = {
            id: object.id,
            version: object.version,
            timestamp: object.timestamp,
            tags: object.tags,
          }
          if object.objtype == 'n'
            ret.update({
              type: 'node',
              lat: T.must(object.lat),
              lon: T.must(object.lon),
            })
          else
            ret.update({
              type: object.objtype == 'w' ? 'way' : 'relation',
              center: {
                lat: T.must(object.lat),
                lon: T.must(object.lon),
              },
            })
          end
        }
      }
    end
  end
end