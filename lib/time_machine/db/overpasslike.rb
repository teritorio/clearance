# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/types'
require './lib/time_machine/osm/tags_matches'
require 'overpass_parser/visitor'

module Db
  extend T::Sig

  class Overpass
    extend T::Sig

    sig {
      params(
        conn: PG::Connection,
        query: String,
      ).returns(T::Array[T::Hash[String, T.untyped]])
    }
    def self.query(conn, query)
      request = OverpassParser.tree(query)[0]
      sql = File.new('/sql/overpasslike.sql').read
      sql += request.to_sql(->(s) { conn.escape_literal(s) })

      conn.exec(sql) { |result|
        result.pluck('jsonb_strip_nulls')
      }
    end
  end
end
