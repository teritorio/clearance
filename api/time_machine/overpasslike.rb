# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/db'

module Overpasslike
  extend T::Sig

  class OverpassCenterResult < T::InexactStruct
    const :lon, Float
    const :lat, Float
  end

  class OverpassResult < Db::ObjectId
    const :tags, Db::OSMTags
    const :lon, T.nilable(Float)
    const :lat, T.nilable(Float)
    const :center, T.nilable(OverpassCenterResult)
  end

  sig {
    params(
      conn: PG::Connection,
      tags: String,
    ).returns(T::Array[T::Hash[Symbol, OverpassResult]])
  }
  def self.query(conn, tags)
    sql_osm_filter_tags = OsmTagsMatches::OsmTagsMatch.new(tags).to_sql(->(s) { conn.method(s) })
    sql = File.new('/sql/overpasslike.sql').read.gsub(':osm_filter_tags', sql_osm_filter_tags)
    conn.exec(sql) { |result|
      result.collect{ |row|
        object = OverpassResult.from_hash(row)

        ret = {
          id: object.id,
          version: object.version,
          tags: object.tags,
        }
        if object.objtype == 'n'
          ret.update({
            type: 'node',
            lat: object.lat,
            lon: object.lon,
          })
        else
          ret.update({
            type: object.objtype == 'w' ? 'way' : 'relation',
            center: {
              lat: object.lat,
              lon: object.lon,
            },
          })
        end
      }
    }
  end
end
