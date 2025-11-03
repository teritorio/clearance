# frozen_string_literal: true
# typed: false

class LochaSemanticGroup < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO #{schema_name}, public;

        ALTER TABLE validations_log
          ADD COLUMN semantic_group integer,
          ADD COLUMN conflation jsonb;
        UPDATE validations_log SET semantic_group = 1;
        UPDATE validations_log SET conflation = '{}'::jsonb;
        ALTER TABLE validations_log
          ALTER COLUMN semantic_group SET NOT NULL,
          ALTER COLUMN conflation SET NOT NULL;
      SQL
    }
  end
end
