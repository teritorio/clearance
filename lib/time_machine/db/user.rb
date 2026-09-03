# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative '../osm/user'

module Db
  extend T::Sig

  sig {
    params(
      conn: PG::Connection,
    ).void
  }
  def self.get_missing_user_ids(conn)
    conn.prepare('user_insert', "
      INSERT INTO
        osm_users
      VALUES
        ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now())
      ON CONFLICT (id)
      DO UPDATE SET
        (id, display_name, account_created, description, company, img_href, changesets_count, traces_count, blocks_received_count, blocks_received_active, updated_at) = (EXCLUDED.id, EXCLUDED.display_name, EXCLUDED.account_created, EXCLUDED.description, EXCLUDED.company, EXCLUDED.img_href, EXCLUDED.changesets_count, EXCLUDED.traces_count, EXCLUDED.blocks_received_count, EXCLUDED.blocks_received_active, now())
    ")

    sql = "(
    SELECT
      DISTINCT osm_base.uid AS id
    FROM
      osm_base
      JOIN osm_changes ON
        osm_changes.objtype = osm_base.objtype AND
        osm_changes.id = osm_base.id
      LEFT JOIN osm_users ON
        osm_users.id = osm_base.uid
    WHERE
      osm_users.id IS NULL

    ) UNION (

    WITH
    osm_changes AS (
      SELECT
        uid,
        max(created) AS max_created
      FROM
        osm_changes
      GROUP BY
        uid
    )
    SELECT
      DISTINCT uid AS id
    FROM
      osm_changes
      LEFT JOIN osm_users ON
        osm_users.id = osm_changes.uid
    WHERE
      osm_users.id IS NULL OR
      max_created >= updated_at OR
      (extract(EPOCH FROM (now() - max_created))) >=
        -- 6h, 12h, 1d, 2d, 4d...
        6 * power(2, floor(log(2, greatest(0, (extract(EPOCH FROM (updated_at - max_created)) / 3600.0 / 6)) + 1))) * 3600
    )"

    user_ids = conn.exec(sql).pluck('id').compact
    i = Osm.fetch_users_by_ids(user_ids).each{ |user|
      conn.exec_prepared('user_insert', [
        user.id,
        user.display_name,
        user.account_created,
        user.description,
        user.company,
        # user.social-links,
        # user.contributor-terms,
        user.img_href,
        # user.roles,
        user.changesets_count,
        user.traces_count,
        user.blocks_received_count,
        user.blocks_received_active,
        # user.blocks_issued_count,
        # user.blocks_issued_active
      ])
    }.size
    puts "Fetch #{i} users"
  end
end
