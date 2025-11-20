# frozen_string_literal: true
# typed: false

class OsmBaseNGeomComputed < ActiveRecord::Migration[7.0]
  def change
    sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public', 'information_schema') AND schema_name NOT LIKE 'pg_%'"
    result = ActiveRecord::Base.connection.execute(sql)
    result.collect{ |row| row['schema_name'] }.each { |schema_name|
      execute <<~SQL # rubocop:disable Rails/ReversibleMigration
        SET search_path TO "#{schema_name}", public;

        ALTER TABLE osm_base_n
          DROP COLUMN geom CASCADE,
          ADD COLUMN geom geometry(Geometry, 4326) NOT NULL GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED
        ;

        CREATE INDEX IF NOT EXISTS osm_base_n_idx_geom ON osm_base_n USING gist(geom);

        CREATE OR REPLACE VIEW osm_base AS (
          SELECT
              'n'::char(1) AS objtype,
              id,
              version,
              changeset_id,
              created,
              uid,
              username,
              tags,
              lon,
              lat,
              NULL::bigint[] AS nodes,
              NULL::jsonb AS members,
              geom
          FROM
              osm_base_n

          ) UNION ALL (

          SELECT
              'w' AS objtype,
              id,
              version,
              changeset_id,
              created,
              uid,
              username,
              tags,
              NULL AS lon,
              NULL AS lat,
              nodes,
              NULL::jsonb AS members,
              geom
          FROM
              osm_base_w

          ) UNION ALL (

          SELECT
              'r' AS objtype,
              id,
              version,
              changeset_id,
              created,
              uid,
              username,
              tags,
              NULL AS lon,
              NULL AS lat,
              NULL::bigint[] AS nodes,
              members,
              geom
          FROM
              osm_base_r
          );

      SQL
    }
  end
end
