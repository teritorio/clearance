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
        ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, now())
      ON CONFLICT (id)
      DO UPDATE SET
        (id, created_at, closed_at, open, \"user\", uid, min_lat, min_lon, max_lat, max_lon, comments_count, changes_count, tags, updated_at) = (EXCLUDED.id, EXCLUDED.created_at, EXCLUDED.closed_at, EXCLUDED.open, EXCLUDED.\"user\", EXCLUDED.uid, EXCLUDED.min_lat, EXCLUDED.min_lon, EXCLUDED.max_lat, EXCLUDED.max_lon, EXCLUDED.comments_count, EXCLUDED.changes_count, EXCLUDED.tags, EXCLUDED.updated_at)
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
      osm_changesets.id IS NULL OR
      osm_changesets.open

    UNION

    SELECT
      DISTINCT changeset_id AS id
    FROM
      osm_changes
      LEFT JOIN osm_changesets ON
        osm_changesets.id = osm_changes.changeset_id
    WHERE
      osm_changesets.id IS NULL OR
      osm_changesets.open OR
      (extract(EPOCH FROM (now() - updated_at))) >=
        -- 6h, 12h, 1d, 2d, 4d...
        6 * power(2, floor(log(2, greatest(0, (extract(EPOCH FROM (updated_at - created_at)) / 3600.0 / 6)) + 1))) * 3600
    "

    changeset_ids = conn.exec(sql).pluck('id').compact
    i = Osm.fetch_changeset_by_ids(changeset_ids).each{ |changeset|
      conn.exec_prepared('changeset_insert', [
          changeset.id,
          changeset.created_at,
          changeset.closed_at,
          changeset.open,
          changeset.user,
          changeset.uid,
          changeset.min_lat,
          changeset.min_lon,
          changeset.max_lat,
          changeset.max_lon,
          changeset.comments_count,
          changeset.changes_count,
          changeset.tags.to_json,
      ])
    }.size
    puts "Fetch #{i} changesets"
  end
end
