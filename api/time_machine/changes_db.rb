# frozen_string_literal: true
# typed: false

require 'sorbet-runtime'
require 'pg'
require './time_machine/types'
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
      'uid' => Integer,
      'username' => String,
      'created' => String,
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
      block: T.proc.params(arg0: OSMChangeObject).void
    ).void
  }
  def self.fetch_changes(&block)
    conn = PG::Connection.new('postgresql://postgres@postgres:5432/postgres')
    conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn)

    conn.exec(File.new('/sql/30_fetch_changes.sql').read) { |result|
      result.each(&block)
    }
  end

  def self.changes_prune
    conn0 = PG::Connection.new('postgresql://postgres@postgres:5432/postgres')
    conn0.transaction{ |conn|
      r = conn.exec(File.new('/sql/10_changes_prune.sql').read)
      puts r.inspect
    }
  end

  def self.apply_unclibled_changes(sql_osm_filter_tags)
    conn0 = PG::Connection.new('postgresql://postgres@postgres:5432/postgres')
    conn0.transaction{ |conn|
      r = conn.exec(File.new('/sql/20_changes_uncibled.sql').read.gsub(':osm_filter_tags', sql_osm_filter_tags))
      puts r.inspect
      r = conn.exec(File.new('/sql/90_changes_apply.sql').read.gsub(':changes_source', 'changes_update'))
      puts r.inspect
    }
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
    const :changeset_id, Integer
    const :created, String
    const :uid, Integer
    const :username, T.nilable(String)
    const :action, T.nilable(Types::ActionType)
    const :validator_uid, T.nilable(Integer)
    const :diff_attribs, Types::HashActions
    const :diff_tags, Types::HashActions
  end

  sig {
    params(
      changes: T::Enumerable[ValidationLog]
    ).void
  }
  def self.apply_logs(changes)
    accepts = changes.select{ |change|
      change.action == 'accept'
    }

    conn0 = PG::Connection.new('postgresql://postgres@postgres:5432/postgres')
    conn0.transaction{ |conn|
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
          ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      ")
      i = 0
      changes.each{ |change|
        i += 1
        conn.exec_prepared('validations_log_insert', [
            change.objtype,
            change.id,
            change.version,
            change.changeset_id,
            change.created,
            change.uid,
            change.username,
            change.action,
            change.validator_uid,
            change.diff_attribs.empty? ? nil : change.diff_attribs.as_json,
            change.diff_tags.empty? ? nil : change.diff_tags.as_json,
        ])
      }
      puts "Logs #{i} changes"
    }
  end

  sig {
    params(
      changes: T::Enumerable[Db::ObjectId]
    ).void
  }
  def self.accept_changes(changes)
    conn0 = PG::Connection.new('postgresql://postgres@postgres:5432/postgres')
    conn0.transaction{ |conn|
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
    }
  end
end
