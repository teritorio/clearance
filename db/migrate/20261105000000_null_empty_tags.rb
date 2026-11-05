# frozen_string_literal: true
# typed: false

class NullEmptyTags < ActiveRecord::Migration[8.1]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        DROP INDEX IF EXISTS osm_base_n_lat_lon_idx_tags;
        UPDATE osm_base_n_lat_lon SET tags = NULL WHERE tags = '{}'::jsonb;
        CREATE INDEX osm_base_n_lat_lon_idx_tags ON osm_base_n_lat_lon USING gin(tags) WHERE tags IS NOT NULL;

        DROP INDEX IF EXISTS osm_base_w_idx_tags;
        UPDATE osm_base_w SET tags = NULL WHERE tags = '{}'::jsonb;
        CREATE INDEX osm_base_w_idx_tags ON osm_base_w USING gin(tags) WHERE tags IS NOT NULL;

        DROP INDEX IF EXISTS osm_base_r_idx_tags;
        UPDATE osm_base_r SET tags = NULL WHERE tags = '{}'::jsonb;
        CREATE INDEX osm_base_r_idx_tags ON osm_base_r USING gin(tags) WHERE tags IS NOT NULL;

        DROP INDEX IF EXISTS osm_changes_idx_tags;
        UPDATE osm_changes SET tags = NULL WHERE tags = '{}'::jsonb;
        CREATE INDEX osm_changes_idx_tags ON osm_changes USING gin(tags) WHERE tags IS NOT NULL;

        UPDATE osm_changes_applyed SET tags = NULL WHERE tags = '{}'::jsonb;
      SQL
    }
  end
end
