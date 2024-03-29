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
        query: String,
      ).returns(T::Array[[OverpassParser::Selectors, T.nilable(T::Array[Integer])]])
    }
    def self.parse(query)
      # Crud overpass extraction of tag selector of nwr line like
      # [out:json][timeout:25];
      # area(id:#{area_ids})->.a;
      # (
      #   nwr[selectors](area.a);
      # );
      # out center meta;

      tree = OverpassParser.tree(query)

      raise unless tree[0][:queries].size == 2

      raise unless tree[0][:queries][0][:type] == :query_object
      raise unless tree[0][:queries][0][:object_type] == 'area'
      raise unless tree[0][:queries][0][:filters].size == 1

      area_ids = tree[0][:queries][0][:filters][0][:ids]
      raise if area_ids.nil?

      area_ids = area_ids.collect{ |i| i.to_i - 3_600_000_000 }

      raise unless tree[0][:queries][1][:type] == :query_group

      tree[0][:queries][1][:queries].collect{ |q|
        raise unless q[:type] == :query_object
        raise unless q[:object_type] == 'nwr'

        [q[:selectors], area_ids]
      }
    end

    sig {
      params(
        conn: PG::Connection,
        query: String,
      ).returns(T::Array[T::Hash[Symbol, OverpassResult]])
    }
    def self.query(conn, query)
      parse(query).collect{ |selector, area_ids|
        db_query(conn, selector, area_ids)
      }.flatten(1).uniq
    end

    sig {
      params(
        conn: PG::Connection,
        selector: OverpassParser::Selectors,
        area_ids: T.nilable(T::Array[Integer]),
      ).returns(T::Array[T::Hash[Symbol, OverpassResult]])
    }
    def self.db_query(conn, selector, area_ids)
      sql_osm_filter_tags = selector.to_sql(->(s) { conn.escape_literal(s) })
      sql = File.new('/sql/overpasslike.sql').read
                .gsub(':osm_filter_tags', sql_osm_filter_tags)
                .gsub(':area_ids', conn.escape_literal(area_ids.to_s))
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
