# frozen_string_literal: true
# typed: false

class ChangesetsBbox < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        ALTER TABLE osm_changesets RENAME COLUMN minlon TO min_lon;
        ALTER TABLE osm_changesets RENAME COLUMN minlat TO min_lat;
        ALTER TABLE osm_changesets RENAME COLUMN maxlon TO max_lon;
        ALTER TABLE osm_changesets RENAME COLUMN maxlat TO max_lat;
      SQL
    }
  end
end
