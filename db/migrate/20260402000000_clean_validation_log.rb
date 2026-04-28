# frozen_string_literal: true
# typed: false

class CleanValidationLog < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        WITH
        osm_base AS (
            SELECT
                osm_base.*
            FROM
                osm_base
                LEFT JOIN osm_changes ON
                    osm_changes.objtype = osm_base.objtype AND
                    osm_changes.id = osm_base.id AND
                    osm_changes.version = osm_base.version AND
                    osm_changes.deleted = false
            WHERE
                osm_changes.id IS NULL
        )
        DELETE FROM
            validations_log
        USING
            osm_base
        WHERE
            validations_log.action != 'accept' AND
            osm_base.objtype = validations_log.after_object->>'objtype' AND
            osm_base.id = (validations_log.after_object->>'id')::bigint AND
            osm_base.version = (validations_log.after_object->>'version')::integer
        ;
      SQL
    }
  end
end
