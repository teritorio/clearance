# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'json'
require 'webcache'


module Changeset
  extend T::Sig

  Changeset = T.type_alias {
    {
      'id' => Integer,
      'created_at' => String,
      'closed_at' => String,
      'open' => T::Boolean,
      'user' => String,
      'uid' => Integer,
      'minlat' => Float,
      'minlon' => Float,
      'maxlat' => Float,
      'maxlon' => Float,
      'comments_count' => Integer,
      'changes_count' => Integer,
      'tags' => T::Hash[String, String],
    }
  }

  sig{
    params(
      id: Integer,
    ).returns(T.nilable(Changeset))
  }
  def self.fetch_id(id)
    cache = WebCache.new(dir: '/projects/cache/changesets/', life: '1d')
    response = cache.get("https://www.openstreetmap.org/api/0.6/changeset/#{id}.json")
    return if !response.success?

    JSON.parse(response.content)['elements'][0].except('type')
  end

  sig {
    params(
      conn: PG::Connection,
    ).void
  }
  def self.get_missing_changeset_ids(conn)
    conn.prepare('changeset_insert', "
      INSERT INTO
        osm_changesets
      VALUES
        ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
    ")

    sql = "
    SELECT
      DISTINCT changeset_id AS id
    FROM
      osm_changes
      LEFT JOIN osm_changesets ON
        osm_changesets.id = osm_changes.changeset_id
    WHERE
      osm_changesets.id IS NULL
    "

    i = conn.exec(sql).collect{ |row|
      fetch_id(row['id'])
    }.compact.collect{ |changeset|
      conn.exec_prepared('changeset_insert', [
          changeset['id'],
          changeset['created_at'],
          changeset['closed_at'],
          changeset['open'],
          changeset['user'],
          changeset['uid'],
          changeset['minlat'],
          changeset['minlon'],
          changeset['maxlat'],
          changeset['maxlon'],
          changeset['comments_count'],
          changeset['changes_count'],
          changeset['tags'].to_json,
      ])
    }.size
    puts "Fetch #{i} changesets"
  end
end
