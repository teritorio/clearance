# frozen_string_literal: true
# typed: false

class ValidationLogIndex < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        CREATE INDEX IF NOT EXISTS validations_log_idx_action ON validations_log(action);
      SQL
    }
  end
end
