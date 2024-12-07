# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/osm/types'
require 'json'
require './lib/time_machine/db/db_conn'
require 'webcache'


module Validation
  extend T::Sig

  class OSMChangeProperties < T::Struct
    const :locha_id, Integer
    const :objtype, String
    const :id, Integer
    const :geom, T.nilable(String)
    const :geos, T.nilable(RGeo::Feature::Geometry)
    prop :geom_distance, T.nilable(T.any(Float, Integer))
    const :deleted, T::Boolean
    const :members, T.nilable(T::Array[Integer])
    const :version, Integer
    const :changesets, T.nilable(T::Array[Osm::Changeset])
    const :username, String
    const :created, String
    const :tags, T::Hash[String, String]
    const :is_change, T::Boolean
    const :group_ids, T.nilable(T::Array[String])

    extend T::Sig

    sig { params(other: OSMChangeProperties).returns(T::Boolean) }
    def eql?(other)
      objtype == other.objtype && id == other.id && (geos || geom) == (other.geos || other.geom)
    end

    sig { returns(Integer) }
    def hash
      [objtype, id, geos&.as_text || geom].hash
    end
  end

  sig {
    params(
      conn: PG::Connection,
      local_srid: Integer,
      locha_cluster_distance: Integer,
      user_groups: T::Hash[String, Configuration::UserGroupConfig],
      block: T.proc.params(arg0: T::Array[[T.nilable(OSMChangeProperties), OSMChangeProperties]]).void
    ).void
  }
  def self.fetch_changes(conn, local_srid, locha_cluster_distance, user_groups, &block)
    user_groups_json = user_groups.collect{ |id, user_group| [id, user_group.polygon_geojson] }.to_json
    conn.exec(File.new('/sql/30_fetch_changes.sql').read)
    results = T.let([], T::Array[[T.nilable(OSMChangeProperties), OSMChangeProperties]])
    last_locha_id = T.let(nil, T.nilable(T::Boolean))
    conn.exec_params(
      'SELECT * FROM fetch_locha_changes(:group_id_polys::jsonb, $1, $2)'.gsub(':group_id_polys', conn.escape_literal(user_groups_json)),
      [local_srid, locha_cluster_distance],
    ) { |result|
      result.each{ |osm_change_object|
        if !last_locha_id.nil? && last_locha_id != osm_change_object['locha_id']
          block.call(results)
          results = []
        end

        ids = { 'locha_id' => osm_change_object['locha_id'], 'objtype' => osm_change_object['objtype'], 'id' => osm_change_object['id'] }
        before = osm_change_object['p'][0]['is_change'] ? nil : OSMChangeProperties.from_hash(osm_change_object['p'][0].merge(ids))
        after = OSMChangeProperties.from_hash(osm_change_object['p'][-1].merge(ids))
        results << [before, after]
        last_locha_id = osm_change_object['locha_id']
      }
    }
  end

  sig {
    params(
      conn: PG::Connection,
    ).void
  }
  def self.changes_prune(conn)
    r = conn.exec(File.new('/sql/10_changes_prune.sql').read)
    puts "  10_changes_prune #{r.inspect}"
  end

  sig {
    params(
      conn: PG::Connection,
      sql_osm_filter_tags: String,
      distance: Integer,
      geojson_polygons: T.nilable(T::Array[T::Hash[String, T.untyped]]),
    ).void
  }
  def self.apply_unclibled_changes(conn, sql_osm_filter_tags, distance, geojson_polygons = nil)
    r = conn.exec(File.new('/sql/20_changes_uncibled.sql').read
      .gsub(':osm_filter_tags', sql_osm_filter_tags)
      .gsub(':polygon', conn.escape_literal(geojson_polygons.to_json))
      .gsub(':distance', distance.to_s))
    puts "  20_changes_uncibled #{r.inspect}"
    r = conn.exec(File.new('/sql/90_changes_apply.sql').read.gsub(':changes_source', 'changes_update'))
    puts "  90_changes_apply #{r.inspect}"
  end

  sig {
    params(
      conn: PG::Connection,
      locha_ids: T::Array[Integer],
    ).void
  }
  def self.apply_lochas_ids(conn, locha_ids)
    sql_create_table = "
      CREATE TEMP TABLE changes_update (
        objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
        id BIGINT NOT NULL,
        version INTEGER NOT NULL,
        deleted BOOLEAN NOT NULL,
        PRIMARY KEY (objtype, id, version, deleted)
      )
    "
    r = conn.exec(sql_create_table)
    puts "  changes_update #{r.inspect}"

    conn.exec("
      INSERT INTO changes_update
      SELECT
        before_object->>'objtype' AS objtype,
        (before_object->>'id')::bigint AS id,
        (before_object->>'version')::integer AS version,
        (before_object->>'deleted')::boolean AS deleted
      FROM
        validations_log
      WHERE
        locha_id = ANY((SELECT array_agg(i)::integer[] FROM json_array_elements_text($1::json) AS t(i))::bigint[]) AND
        before_object IS NOT NULL
      UNION ALL
      SELECT
        after_object->>'objtype' AS objtype,
        (after_object->>'id')::bigint AS id,
        (after_object->>'version')::integer AS version,
        (after_object->>'deleted')::boolean AS deleted
      FROM
        validations_log
      WHERE
        locha_id = ANY((SELECT array_agg(i)::integer[] FROM json_array_elements_text($1::json) AS t(i))::bigint[]) AND
        after_object IS NOT NULL
    ", [
      locha_ids.to_json,
    ])
    puts "Apply on #{locha_ids.size} loCha"

    validate_changes(conn)
  end

  sig {
    params(
      conn: PG::Connection,
      changes: T::Enumerable[ValidationLog]
    ).void
  }
  def self.apply_changes(conn, changes)
    sql_create_table = "
      CREATE TEMP TABLE changes_update (
        objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
        id BIGINT NOT NULL,
        version INTEGER NOT NULL,
        deleted BOOLEAN NOT NULL,
        PRIMARY KEY (objtype, id)
      )
    "
    r = conn.exec(sql_create_table)
    puts "  changes_update #{r.inspect}"

    conn.prepare('changes_update_insert', 'INSERT INTO changes_update VALUES ($1, $2, $3, $4)')
    i = 0
    changes.each{ |change|
      i += 1
      conn.exec_prepared('changes_update_insert', [change.after_objects.objtype, change.after_objects.id, change.after_objects.version, change.after_objects.deleted])
    }
    puts "Apply on #{i} changes"

    validate_changes(conn)
  end

  sig {
    params(
      conn: PG::Connection,
    ).void
  }
  def self.validate_changes(conn)
    r = conn.exec(File.new('/sql/40_validated_changes.sql').read)
    puts "  40_validated_changes #{r.inspect}"

    r = conn.exec(File.new('/sql/90_changes_apply.sql').read.gsub(':changes_source', 'changes_source'))
    puts " 90_changes_apply #{r.inspect}"
  end

  class ValidationLogMatch < T::InexactStruct
    const :user_groups, T.nilable(T::Array[String])
    const :sources, T.nilable(T::Array[String])
    const :selectors, T::Array[String]
    const :name, T.nilable(T::Hash[String, String])
    const :icon, T.nilable(String)
  end

  class ValidationLog < T::InexactStruct
    const :locha_id, Integer
    const :before_objects, T.nilable(Osm::ObjectChangeId)
    const :after_objects, Osm::ObjectChangeId
    const :changeset_ids, T.nilable(T::Array[Integer])
    const :created, String
    const :matches, T::Array[ValidationLogMatch]
    const :action, T.nilable(ActionType)
    const :validator_uid, T.nilable(Integer)
    const :diff_attribs, HashActions
    const :diff_tags, HashActions
  end

  sig {
    params(
      conn: PG::Connection,
      changes: T::Enumerable[ValidationLog]
    ).void
  }
  def self.apply_logs(conn, changes)
    accepts = changes.select{ |change|
      change.action == 'accept'
    }

    apply_changes(conn, accepts)

    conn.exec("
      DELETE FROM
        validations_log
      WHERE
        action IS NULL OR
        action = 'reject'
    ")

    conn.prepare('validations_log_insert', "
      INSERT INTO
        validations_log
      VALUES
        (
          (SELECT array_agg(i)::integer[] FROM json_array_elements_text($1::json) AS t(i)),
          $2, $3::json, $4, $5, $6, $7, $8, $9::json, $10::json
        )
    ")
    i = 0
    changes.each{ |change|
      i += 1
      conn.exec_prepared('validations_log_insert', [
        change.changeset_ids&.to_json,
        change.created,
        change.matches.to_json,
        change.action,
        change.validator_uid,
        change.diff_attribs.empty? ? nil : change.diff_attribs.as_json.to_json,
        change.diff_tags.empty? ? nil : change.diff_tags.as_json.to_json,
        change.locha_id,
        change.before_objects&.to_json,
        change.after_objects.to_json,
      ])
    }
    puts "Logs #{i} changes"
  end

  sig {
    params(
      conn: PG::Connection,
      locha_ids: T::Array[Integer],
      validator_uid: T.nilable(Integer),
    ).void
  }
  def self.accept_changes(conn, locha_ids, validator_uid = nil)
    apply_lochas_ids(conn, locha_ids)

    conn.exec("
      UPDATE
        validations_log
      SET
        action = 'accept',
        validator_uid = $2
      WHERE
        locha_id = ANY((SELECT array_agg(i)::integer[] FROM json_array_elements_text($1::json) AS t(i))::bigint[])
    ", [
      locha_ids.to_json,
      validator_uid,
    ])
  end
end
