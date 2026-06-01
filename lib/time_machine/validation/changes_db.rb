# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'json'
require 'webcache'
require 'openstreetmap_logical_history'
require './lib/time_machine/validation/types'
require './lib/time_machine/osm/types'
require './lib/time_machine/db/db_conn'
require 'rgeo'


module Validation
  extend T::Sig

  class OSMChangeProperties < OSMLogicalHistory::OSMObject
    extend T::Sig

    sig { returns(T.nilable(Osm::Changeset)) }
    attr_reader :changeset

    sig { returns(T::Boolean) }
    attr_reader :is_change

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :group_ids

    sig {
      params(
        objtype: String,
        id: Integer,
        geojson_geometry: T.nilable(String),
        geos_factory: T.proc.params(geom: String).returns(T.nilable(RGeo::Feature::Geometry)),
        deleted: T::Boolean,
        members: T.nilable(T::Array[Integer]),
        version: Integer,
        username: T.nilable(String),
        created: String,
        tags: T::Hash[String, String],
        changeset: T.nilable(Osm::Changeset),
        is_change: T::Boolean,
        group_ids: T.nilable(T::Array[String]),
      ).void
    }
    def initialize(objtype:, id:, geojson_geometry:, geos_factory:, deleted:, members:, version:, username:, created:, tags:, changeset:, is_change:, group_ids:) # rubocop:disable Metrics/ParameterLists
      super(
        objtype: objtype,
        id: id,
        geojson_geometry: geojson_geometry,
        geos_factory: geos_factory,
        deleted: deleted,
        members: members,
        version: version,
        username: username,
        created: created,
        tags: tags,
      )
      @changeset = changeset
      @is_change = is_change
      @group_ids = group_ids
    end

    sig {
      params(
        hash: T::Hash[String, T.untyped]
      ).returns(OSMChangeProperties)
    }
    def self.from_hash(hash)
      OSMChangeProperties.new(
        objtype: hash['objtype'],
        id: hash['id'],
        geojson_geometry: hash['geojson_geometry'],
        geos_factory: hash['geos_factory'],
        deleted: hash['deleted'],
        members: hash['members'],
        version: hash['version'],
        username: hash['username'],
        created: hash['created'],
        tags: hash['tags'],
        changeset: hash['changeset'].nil? ? nil : Osm::Changeset.from_hash(hash['changeset']),
        is_change: hash['is_change'],
        group_ids: hash['group_ids'],
      )
    end

    sig {
      returns(T::Hash[String, T.untyped])
    }
    def to_h
      {
        'objtype' => objtype,
        'id' => id,
        'geojson_geometry' => geojson_geometry,
        'deleted' => deleted,
        'members' => members,
        'version' => version,
        'username' => username,
        'created' => created,
        'tags' => tags,
        'changeset' => changeset,
        'is_change' => is_change,
        'group_ids' => group_ids,
      }
    end

    sig {
      params(
        kwargs: T.untyped
      ).returns(OSMChangeProperties)
    }
    def with(**kwargs)
      o = OSMChangeProperties.new(
        objtype: kwargs.fetch(:objtype, objtype),
        id: kwargs.fetch(:id, id),
        geojson_geometry: kwargs.fetch(:geojson_geometry, geojson_geometry),
        geos_factory: kwargs.fetch(:geos_factory, geos_factory),
        deleted: kwargs.fetch(:deleted, deleted),
        members: kwargs.fetch(:members, members),
        version: kwargs.fetch(:version, version),
        username: kwargs.fetch(:username, username),
        created: kwargs.fetch(:created, created),
        tags: kwargs.fetch(:tags, tags),
        changeset: kwargs.fetch(:changeset, changeset),
        is_change: kwargs.fetch(:is_change, is_change),
        group_ids: kwargs.fetch(:group_ids, group_ids),
      )
      o.geos = kwargs[:geos] if kwargs[:geos]
      o
    end
  end

  sig {
    params(
      osm_change_object: T.untyped,
      local_srid: Integer
    ).returns([T.nilable(OSMChangeProperties), OSMChangeProperties])
  }
  def self.convert_locha_item(osm_change_object, local_srid)
    geos_factory = OSMLogicalHistory.build_geos_factory(local_srid)
    ids = { 'objtype' => osm_change_object['objtype'], 'id' => osm_change_object['id'], 'geos_factory' => geos_factory }
    before = osm_change_object['p'][0]['is_change'] ? nil : OSMChangeProperties.from_hash(osm_change_object['p'][0].merge(ids))
    after = OSMChangeProperties.from_hash(osm_change_object['p'][-1].merge(ids))
    [before, after]
  end

  sig {
    params(
      conn: PG::Connection,
      local_srid: Integer,
      locha_cluster_distance: Integer,
      user_groups: T::Hash[String, Configuration::UserGroupConfig],
      block: T.proc.params(
        locha_id: Integer,
        results: T::Array[[T.nilable(OSMChangeProperties), OSMChangeProperties]],
      ).void
    ).void
  }
  def self.fetch_changes(conn, local_srid, locha_cluster_distance, user_groups, &block)
    user_groups_json = user_groups.collect{ |id, user_group| [id, user_group.polygon_geojson] }.to_json
    conn.exec(File.new('/sql/30_set_locha_id.sql').read
      .gsub(':proj', local_srid.to_s)
      .gsub(':distance', locha_cluster_distance.to_s))
    conn.exec(File.new('/sql/31_fetch_changes.sql').read)
    results = T.let([], T::Array[[T.nilable(OSMChangeProperties), OSMChangeProperties]])
    last_locha_id = T.let(nil, T.nilable(Integer))
    conn.exec_params(
      'SELECT * FROM fetch_locha_changes(:group_id_polys::jsonb)'.gsub(':group_id_polys', conn.escape_literal(user_groups_json)),
    ) { |result|
      result.each{ |osm_change_object|
        locha_id = Integer(osm_change_object['locha_id'])
        if !last_locha_id.nil? && last_locha_id != locha_id
          block.call(last_locha_id, results)
          results = []
        end

        results << convert_locha_item(osm_change_object, local_srid)
        last_locha_id = locha_id
      }

      if !results.empty?
        block.call(T.must(last_locha_id), results)
      end
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
      osm_tags_matches: Osm::TagsMatches,
      proj: Integer,
      distance: Integer,
      geojson_polygons: T.nilable(T::Array[T::Hash[String, T.untyped]]),
    ).void
  }
  def self.apply_unclibled_changes(conn, osm_tags_matches, proj, distance, geojson_polygons = nil)
    escape_literal = proc { |s| conn.escape_literal(s) }
    sql_osm_filter_tags = osm_tags_matches.to_sql('postgres', '_', escape_literal)
    sql_osm_diff_tags = osm_tags_matches.to_sql_changes('postgres', 'base', 'changes', escape_literal)
    conn.exec(File.new('/sql/20_changes_uncibled.sql').read
      .gsub(':osm_filter_tags', sql_osm_filter_tags)
      .gsub(':osm_diff_tags', sql_osm_diff_tags)
      .gsub(':polygon', conn.escape_literal(geojson_polygons.to_json))
      .gsub(':proj', proj.to_s)
      .gsub(':distance', distance.to_s))
    conn.exec(File.new('/sql/90_changes_apply.sql').read.gsub(':changes_source', 'changes_update'))
  end

  sig {
    params(
      conn: PG::Connection,
      locha_ids: T::Array[Integer],
      links_index: T.nilable(Integer),
    ).void
  }
  def self.apply_lochas_ids(conn, locha_ids, links_index)
    raise 'Invalid locha id paramter' if !links_index.nil? && locha_ids.size > 1

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
        objtype,
        id,
        version,
        deleted
      FROM
        osm_changes
      WHERE
        locha_id = ANY((SELECT array_agg(i)::integer[] FROM json_array_elements_text($1::json) AS t(i))::bigint[])
      ON CONFLICT (objtype, id, version, deleted)
      DO NOTHING
    ", [
      locha_ids.to_json,
    ])
    puts "Apply on #{locha_ids.size} loCha"

    validate_changes(conn)
  end


  sig {
    params(
      conn: PG::Connection,
      locha_id_semantic_groups: T::Array[[Integer, Integer]],
    ).void
  }
  def self.apply_locha_id_semantic_groups(conn, locha_id_semantic_groups)
    sql_create_table = "
      CREATE TEMP TABLE changes_update (
        objtype CHAR(1) CHECK(objtype IN ('n', 'w', 'r')),
        id BIGINT NOT NULL,
        version INTEGER NOT NULL,
        deleted BOOLEAN NOT NULL,
        PRIMARY KEY (objtype, id, version, deleted)
      )
    "
    conn.exec(sql_create_table)

    sql_create_table = "
      CREATE TEMP TABLE locha_id_semantic_group (
        locha_id INTEGER NOT NULL,
        semantic_group INTEGER NOT NULL,
        PRIMARY KEY (locha_id, semantic_group)
      )
    "
    conn.exec(sql_create_table)

    r = conn.exec_params("
      INSERT INTO locha_id_semantic_group (locha_id, semantic_group)
      SELECT
        (data->>0)::integer,
        (data->>1)::integer
      FROM
        json_array_elements($1::json) AS t(data)
    ", [
      locha_id_semantic_groups.to_json,
    ])
    puts "  locha_id_semantic_group count #{r.inspect}"

    r = conn.exec("
      INSERT INTO changes_update
      SELECT
        objtype,
        id,
        version,
        deleted
      FROM
        locha_id_semantic_group
        JOIN validations_log ON
          validations_log.locha_id = locha_id_semantic_group.locha_id AND
          validations_log.semantic_group = locha_id_semantic_group.semantic_group
        JOIN osm_changes ON
          osm_changes.objtype = validations_log.after_object->>'objtype' AND
          osm_changes.id = (validations_log.after_object->>'id')::bigint
      ON CONFLICT (objtype, id, version, deleted)
      DO NOTHING
    ")
    puts "  changes_update count #{r.inspect}"

    validate_changes(conn)
  end

  sig {
    params(
      conn: PG::Connection,
      changes: T::Enumerable[ValidationLog]
    ).void
  }
  def self.apply_changes(conn, changes)
    locha_id_semantic_groups = changes.collect{ |change| [change.locha_id, change.semantic_group] }.uniq
    apply_locha_id_semantic_groups(conn, locha_id_semantic_groups)
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
    const :semantic_group, Integer
    const :before_objects, T.nilable(Osm::ObjectChangeId)
    const :after_objects, T.nilable(Osm::ObjectChangeId)
    const :created, String
    const :conflation_reason, OSMLogicalHistory::Conflation::ConflationReason
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
    locha_accepted = changes.collect(&:locha_id) - changes.select{ |change| change.action != 'accept' }.collect(&:locha_id)
    apply_lochas_ids(conn, locha_accepted, nil)

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
        ($1, $2::json, $3, $4, $5, $6, $7, $8::json, $9::json, $10, $11::json)
    ")
    i = 0
    changes.each{ |change|
      i += 1
      conn.exec_prepared('validations_log_insert', [
        change.created,
        change.matches.to_json,
        change.action,
        change.validator_uid,
        change.diff_attribs.empty? ? nil : change.diff_attribs.as_json.to_json,
        change.diff_tags.empty? ? nil : change.diff_tags.as_json.to_json,
        change.locha_id,
        change.before_objects&.to_json,
        change.after_objects.to_json,
        change.semantic_group,
        change.conflation_reason.to_json,
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
  def self.accept_lochas(conn, locha_ids, validator_uid = nil)
    apply_lochas_ids(conn, locha_ids, nil)

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

  sig {
    params(
      conn: PG::Connection,
      locha_id: Integer,
      links_index: T.nilable(Integer),
      validator_uid: T.nilable(Integer),
    ).void
  }
  def self.accept_locha(conn, locha_id, links_index, validator_uid = nil)
    apply_lochas_ids(conn, [locha_id], links_index)

    conn.exec("
      UPDATE
        validations_log
      SET
        action = 'accept',
        validator_uid = $3
      WHERE
        locha_id = $1 AND
        ($2 IS NULL OR semantic_group = $2)
    ", [
      locha_id,
      links_index,
      validator_uid,
    ])
  end
end
