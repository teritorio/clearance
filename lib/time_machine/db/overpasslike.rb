# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/types'
require './lib/time_machine/osm/tags_matches'

module Db
  extend T::Sig

  class Overpass
    extend T::Sig

    sig {
      params(
        conn: PG::Connection,
        query: String,
        srid: Integer,
      ).returns(T::Array[T::Hash[String, T.untyped]])
    }
    def self.query(conn, query, srid)
      request = OverpassParserRuby.parse(query)
      sql = File.new('/sql/overpasslike.sql').read
      sql += request.to_sql('postgres', srid, proc { |s| conn.escape_literal(s) })

      conn.exec(sql) { |result|
        result.pluck('j')
      }
    end
  end
end
