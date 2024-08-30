# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative '../osm/changeset'

module Db
  extend T::Sig

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
      DISTINCT osm_base.changeset_id AS id
    FROM
      osm_base
      JOIN osm_changes ON
        osm_changes.objtype = osm_base.objtype AND
        osm_changes.id = osm_base.id
        LEFT JOIN osm_changesets ON
          osm_changesets.id = osm_base.changeset_id
    WHERE
      osm_changesets.id IS NULL

    UNION

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
      Osm.fetch_changeset_by_id(row['id'])
    }.compact.collect{ |changeset|
      conn.exec_prepared('changeset_insert', [
          changeset['id'],
          changeset['created_at'],
          changeset['closed_at'],
          changeset['open'],
          changeset['user'],
          changeset['uid'],
          changeset['min_lat'],
          changeset['min_lon'],
          changeset['max_lat'],
          changeset['max_lon'],
          changeset['comments_count'],
          changeset['changes_count'],
          changeset['tags'].to_json,
      ])
    }.size
    puts "Fetch #{i} changesets"
  end
end
