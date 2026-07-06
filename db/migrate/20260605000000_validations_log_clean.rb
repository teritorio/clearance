# frozen_string_literal: true
# typed: false

class ValidationsLogClean < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql).to_a
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        UPDATE
          validations_log
        SET
          before_object = nullif(before_object, 'null'::jsonb) - '_extra_props',
          after_object = nullif(after_object, 'null'::jsonb) - '_extra_props'
        ;

        ALTER TABLE validations_log ADD CHECK (before_object IS NULL OR jsonb_typeof(before_object) = 'object');
        ALTER TABLE validations_log ADD CHECK (after_object IS NULL OR jsonb_typeof(after_object) = 'object');
      SQL
    }

    puts "\n\n-- RUN VACUUM FULL validations_log for each schema to reclaim space. --\n\n"
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      puts("VACUUM FULL \"#{schema_name}\".validations_log;\n")
    }
  end
end
