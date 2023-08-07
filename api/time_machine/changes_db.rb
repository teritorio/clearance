# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/types'
require './time_machine/changeset'
require 'json'
require './time_machine/db'


module ChangesDb
  extend T::Sig

  OSMChangeProperties = T.type_alias {
    {
      'lat' => T.nilable(Float),
      'lon' => T.nilable(Float),
      'nodes' => T.nilable(T::Array[Integer]),
      'deleted' => T::Boolean,
      'members' => T.nilable(T::Array[Integer]),
      'version' => Integer,
      'changeset_id' => Integer,
      'changeset' => T.nilable(Changeset::Changeset),
      'tags' => T::Hash[String, String],
      'change_distance' => T.any(Float, Integer),
    }
  }

  OSMChangeObject = T.type_alias {
    {
      'objtype' => String,
      'id' => Integer,
      'p' => T::Array[OSMChangeProperties]
    }
  }

  sig {
    params(
      conn: PG::Connection,
      block: T.proc.params(arg0: OSMChangeObject).void
    ).void
  }
  def self.fetch_changes(conn, &block)
    conn.exec(File.new('/sql/30_fetch_changes.sql').read) { |result|
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
      sql_osm_filter_tags: String
    ).void
  }
  def self.apply_unclibled_changes(conn, sql_osm_filter_tags)
    r = conn.exec(File.new('/sql/20_changes_uncibled.sql').read.gsub(':osm_filter_tags', sql_osm_filter_tags))
    puts r.inspect
    r = conn.exec(File.new('/sql/90_changes_apply.sql').read.gsub(':changes_source', 'changes_update'))
    puts r.inspect
  end

  sig {
    params(
      conn: PG::Connection,
      changes: T::Enumerable[Db::ObjectId]
    ).void
  }
  def self.apply_changes(conn, changes)
    sql_create_table = "
      CREATE TEMP TABLE changes_update (
        objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
        id BIGINT NOT NULL,
        version INTEGER NOT NULL
      )
    "
    r = conn.exec(sql_create_table)
    puts r.inspect

    conn.prepare('changes_update_insert', 'INSERT INTO changes_update VALUES ($1, $2, $3)')
    i = 0
    changes.each{ |change|
      i += 1
      conn.exec_prepared('changes_update_insert', [change.objtype, change.id, change.version])
    }
    puts "Apply on #{i} changes"

    r = conn.exec(File.new('/sql/40_validated_changes.sql').read)
    puts r.inspect

    r = conn.exec(File.new('/sql/90_changes_apply.sql').read.gsub(':changes_source', 'changes_source'))
    puts r.inspect
  end

  class ValidationLog < Db::ObjectId
    const :changeset_ids, T::Array[Integer]
    const :action, T.nilable(Types::ActionType)
    const :validator_uid, T.nilable(Integer)
    const :diff_attribs, Types::HashActions
    const :diff_tags, Types::HashActions
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
          $1, $2, $3,
          (SELECT array_agg(i)::integer[] FROM json_array_elements_text($4::json) AS t(i)),
          $5, $6, $7, $8
        )
    ")
    i = 0
    changes.each{ |change|
      i += 1
      conn.exec_prepared('validations_log_insert', [
          change.objtype,
          change.id,
          change.version,
          change.changeset_ids.to_json,
          change.action,
          change.validator_uid,
          change.diff_attribs.empty? ? nil : change.diff_attribs.as_json.to_json,
          change.diff_tags.empty? ? nil : change.diff_tags.as_json.to_json,
      ])
    }
    puts "Logs #{i} changes"
  end

  sig {
    params(
      conn: PG::Connection,
      changes: T::Enumerable[Db::ObjectId]
    ).void
  }
  def self.accept_changes(conn, changes)
    apply_changes(conn, changes)

    conn.prepare('validations_log_delete', "
        DELETE FROM
          validations_log
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
      ])
    }
  end
end
