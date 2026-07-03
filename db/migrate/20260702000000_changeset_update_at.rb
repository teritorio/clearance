# frozen_string_literal: true
# typed: false

class ChangesetUpdateAt < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        ALTER TABLE osm_changesets
          ADD COLUMN IF NOT EXISTS updated_at timestamp(0) without time zone
            DEFAULT to_timestamp(0) NOT NULL;
      SQL
    }
  end
end
