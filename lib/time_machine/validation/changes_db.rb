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

  OSMChangeProperties = T.type_alias {
    {
      'geom' => T.untyped,
      'geom_distance' => T.any(Float, Integer),
      'deleted' => T::Boolean,
      'members' => T.nilable(T::Array[Integer]),
      'version' => Integer,
      'changesets' => T.nilable(T::Array[Osm::Changeset]),
      'username' => String,
      'created' => String,
      'tags' => T::Hash[String, String],
      'is_change' => T::Boolean,
      'group_ids' => T.nilable(T::Array[String]),
    }
  }

  OSMLochaObject = T.type_alias {
    {
      'locha_id' => Integer,
      'objtype' => String,
      'id' => Integer,
      'p' => T::Array[OSMChangeProperties]
    }
  }

  sig {
    params(
      conn: PG::Connection,
      local_srid: Integer,
      locha_cluster_distance: Integer,
      user_groups: T::Hash[String, Configuration::UserGroupConfig],
      block: T.proc.params(arg0: OSMLochaObject).void
    ).void
  }
  def self.fetch_changes(conn, local_srid, locha_cluster_distance, user_groups, &block)
    user_groups_json = user_groups.collect{ |id, user_group| [id, user_group.polygon_geojson] }.to_json
    conn.exec(File.new('/sql/30_fetch_changes.sql').read)
    conn.exec_params(
      'SELECT * FROM fetch_locha_changes(:group_id_polys::jsonb, $1, $2)'.gsub(':group_id_polys', conn.escape_literal(user_groups_json)),
      [local_srid, locha_cluster_distance],
    ) { |result|
      result.each(&block)
    }
  end

  sig {
    params(
      conn: PG::Connection,
    ).void
  }
  def self.changes_prune(conn)
    r = conn.exec(File.new('/sql/10_changes_prune.sql').read)
    puts r.inspect
  end

  sig {
    params(
      conn: PG::Connection,
      sql_osm_filter_tags: String,
      geojson_polygons: T.nilable(T::Array[T::Hash[String, T.untyped]]),
    ).void
  }
  def self.apply_unclibled_changes(conn, sql_osm_filter_tags, geojson_polygons = nil)
    r = conn.exec(File.new('/sql/20_changes_uncibled.sql').read
      .gsub(':osm_filter_tags', sql_osm_filter_tags)
      .gsub(':polygon', conn.escape_literal(geojson_polygons.to_json)))
    puts r.inspect
    r = conn.exec(File.new('/sql/25_transitives_changes.sql').read)
    puts r.inspect
    r = conn.exec(File.new('/sql/90_changes_apply.sql').read.gsub(':changes_source', 'changes_update'))
    puts r.inspect
  end

  sig {
    params(
      conn: PG::Connection,
      changes: T::Enumerable[Osm::ObjectChangeId]
    ).void
  }
  def self.apply_changes(conn, changes)
    sql_create_table = "
      CREATE TEMP TABLE changes_update (
        objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
        id BIGINT NOT NULL,
        version INTEGER NOT NULL,
        deleted BOOLEAN NOT NULL
      )
    "
    r = conn.exec(sql_create_table)
    puts r.inspect

    conn.prepare('changes_update_insert', 'INSERT INTO changes_update VALUES ($1, $2, $3, $4)')
    i = 0
    changes.each{ |change|
      i += 1
      conn.exec_prepared('changes_update_insert', [change.objtype, change.id, change.version, change.deleted])
    }
    puts "Apply on #{i} changes"

    r = conn.exec(File.new('/sql/40_validated_changes.sql').read)
    puts r.inspect

    r = conn.exec(File.new('/sql/90_changes_apply.sql').read.gsub(':changes_source', 'changes_source'))
    puts r.inspect
  end

  class ValidationLogMatch < T::InexactStruct
    const :user_groups, T.nilable(T::Array[String])
    const :sources, T.nilable(T::Array[String])
    const :selectors, T::Array[String]
    const :name, T.nilable(T::Hash[String, String])
    const :icon, T.nilable(String)
  end

  class ValidationLog < Osm::ObjectChangeId
    const :locha_id, Integer
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
          $1, $2, $3, $4,
          (SELECT array_agg(i)::integer[] FROM json_array_elements_text($5::json) AS t(i)),
          $6, $7::json, $8, $9, $10, $11, $12
        )
      -- FIXME rather than check for conflicts on each, better validate data by lochas and do not re-insert objects changed only by transitivity.
      ON CONFLICT ON CONSTRAINT validations_log_pkey
      DO NOTHING
    ")
    i = 0
    changes.each{ |change|
      i += 1
      conn.exec_prepared('validations_log_insert', [
        change.objtype,
        change.id,
        change.version,
        change.deleted,
        change.changeset_ids&.to_json,
        change.created,
        change.matches.to_json,
        change.action,
        change.validator_uid,
        change.diff_attribs.empty? ? nil : change.diff_attribs.as_json.to_json,
        change.diff_tags.empty? ? nil : change.diff_tags.as_json.to_json,
        change.locha_id,
      ])
    }
    puts "Logs #{i} changes"
  end

  sig {
    params(
      conn: PG::Connection,
      changes: T::Enumerable[Osm::ObjectChangeId],
      validator_uid: T.nilable(Integer),
    ).void
  }
  def self.accept_changes(conn, changes, validator_uid = nil)
    apply_changes(conn, changes)

    conn.prepare('validations_log_delete', "
      UPDATE
        validations_log
      SET
        action = 'accept',
        validator_uid = $4
      WHERE
        objtype = $1 AND
        id = $2 AND
        version = $3
    ")
    changes.each{ |change|
      conn.exec_prepared('validations_log_delete', [
        change.objtype,
        change.id,
        change.version,
        validator_uid,
      ])
    }
  end
end
