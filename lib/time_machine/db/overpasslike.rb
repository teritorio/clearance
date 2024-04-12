# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/types'
require './lib/time_machine/osm/tags_matches'
require 'overpass_parser/visitor'
require 'overpass_parser/sql_dialect/postgres'

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
      dialect = OverpassParser::SqlDialect::Postgres.new(postgres_escape_literal: ->(s) { conn.escape_literal(s) })
      sql += request.to_sql(dialect)

      conn.exec(sql) { |result|
        result.pluck('j')
      }
    end
  end
end
