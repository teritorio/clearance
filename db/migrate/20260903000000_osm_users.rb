# frozen_string_literal: true
# typed: false

class OsmUsers < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        DROP TABLE IF EXISTS osm_users CASCADE;
        CREATE TABLE osm_users (
            id BIGINT NOT NULL,
            display_name TEXT NOT NULL,
            account_created TIMESTAMP (0) WITHOUT TIME ZONE NOT NULL,
            description TEXT,
            company TEXT,
            img_href TEXT,
            changesets_count INTEGER NOT NULL,
            traces_count INTEGER NOT NULL,
            blocks_received_count INTEGER,
            blocks_received_active INTEGER,
            updated_at TIMESTAMP (0) WITHOUT TIME ZONE NOT NULL
        );
        ALTER TABLE osm_users ADD PRIMARY KEY(id);
      SQL
    }
  end
end
