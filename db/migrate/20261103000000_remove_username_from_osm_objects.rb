# frozen_string_literal: true
# typed: false

class RemoveUsernameFromOsmObjects < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      # rubocop:disable Rails/ReversibleMigration
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        ALTER TABLE osm_users
          ALTER COLUMN account_created SET DEFAULT to_timestamp(0),
          ALTER COLUMN updated_at SET DEFAULT to_timestamp(0),
          ALTER COLUMN changesets_count DROP NOT NULL,
          ALTER COLUMN traces_count DROP NOT NULL
        ;

        INSERT INTO osm_users (
          id,
          display_name
        )
        SELECT DISTINCT ON (uid)
          uid,
          username
        FROM (
          SELECT uid, username, created FROM osm_changes WHERE uid IS NOT NULL AND username IS NOT NULL
          UNION ALL
          SELECT uid, username, created FROM osm_changes_applyed WHERE uid IS NOT NULL AND username IS NOT NULL
          UNION ALL
          SELECT uid, username, created FROM osm_base_n WHERE uid IS NOT NULL AND username IS NOT NULL
          UNION ALL
          SELECT uid, username, created FROM osm_base_w WHERE uid IS NOT NULL AND username IS NOT NULL
          UNION ALL
          SELECT uid, username, created FROM osm_base_r WHERE uid IS NOT NULL AND username IS NOT NULL
        ) AS usernames
        ORDER BY uid, created DESC NULLS LAST
        ON CONFLICT (id) DO NOTHING
        ;
      SQL

      %w[
        osm_base_n
        osm_base_w
        osm_base_r
        osm_changes
        osm_changes_applyed
      ].each{ |table_name|
        execute "ALTER TABLE #{table_name} DROP COLUMN IF EXISTS username CASCADE"
      }
      # rubocop:enable Rails/ReversibleMigration
    }
  end
end
