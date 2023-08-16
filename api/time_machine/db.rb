# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'pg'
require './time_machine/types'
require './time_machine/state_file'
require './time_machine/changeset'
require 'json'
require 'nokogiri'
require 'zlib'
require 'fileutils'
require 'bzip2/ffi'

module Db
  extend T::Sig

  class DbConnRead
    extend T::Sig

    sig {
      params(
        project: String,
        block: T.proc.params(conn: PG::Connection).void,
      ).void
    }
    def self.conn(project, &block)
      conn0 = PG::Connection.new('postgresql://postgres@postgres:5432/postgres')
      conn0.type_map_for_results = PG::BasicTypeMapForResults.new(conn0)

      # Avoid SQL injection
      raise 'Invalid project name' if !(project =~ /[-A-Za-z0-9_]+/)

      conn0.exec("SET search_path = #{project},public")
      block.call(conn0)
    end
  end

  class DbConnWrite < DbConnRead
    extend T::Sig

    sig {
      params(
        project: String,
        block: T.proc.params(conn: PG::Connection).void,
      ).void
    }
    def self.conn(project, &block)
      super(project) { |conn0|
        conn0.transaction(&block)
      }
    end
  end

  OSMTags = T.type_alias { T::Hash[String, String] }

  class OSMRelationMember < T::InexactStruct
    const :ref, Integer
    const :role, String
    const :type, String
  end

  OSMRelationMembers = T.type_alias { T::Array[OSMRelationMember] }

  class ObjectId < T::InexactStruct
    const :objtype, String
    const :id, Integer
    const :version, Integer
  end

  class ObjectBase < ObjectId
    const :changeset_id, Integer
    const :changeset, T.nilable(Changeset::Changeset)
    const :created, Time
    const :uid, Integer
    const :username, T.nilable(String)
    const :tags, OSMTags
    const :lon, T.nilable(Float)
    const :lat, T.nilable(Float)
    const :nodes, T.nilable(T::Array[Integer])
    const :members, T.nilable(T::Array[OSMRelationMember])
  end

  class ObjectChanges < ObjectBase
    const :deleted, T::Boolean
  end

  sig {
    params(
      object: Db::ObjectBase,
    ).returns(T::Hash[Symbol, String])
  }
  def self.as_osm_xml_attribs(object)
    {
      id: object.id,
      version: object.version,
      changeset: object.changeset_id,
      timestamp: object.created.iso8601(0).gsub('+00:00', 'Z'),
      uid: object.uid,
      user: object.username,
    }
  end

  sig {
    params(
      xml: T.untyped, # Nokogiri::XML::Builder,
      tags: OSMTags,
    ).void
  }
  def self.as_osm_xml_tags(xml, tags)
    tags.each{ |k, v|
      xml.tag(k: k, v: v)
    }
  end

  sig {
    params(
      object: ObjectBase,
    ).returns(String)
  }
  def self.as_osm_xml(object)
    Nokogiri::XML::Builder.new { |xml|
      case object.objtype
      when 'n'
        xml.node(
          **as_osm_xml_attribs(object),
          lon: object.lon,
          lat: object.lat,
        ) {
          as_osm_xml_tags(xml, object.tags)
        }
      when 'w'
        xml.way(**as_osm_xml_attribs(object)) {
          object.nodes&.each{ |node_id|
            xml.nd(ref: node_id)
          }
          as_osm_xml_tags(xml, object.tags)
        }
      when 'r'
        xml.relation(**as_osm_xml_attribs(object)) {
          object.members&.each{ |member|
            xml.member(
              type: { 'n' => 'node', 'w' => 'way', 'r' => 'relation' }[member.type],
              ref: member.ref,
              role: member.role
            )
          }
          as_osm_xml_tags(xml, object.tags)
        }
      end
    }.doc.root.to_s
  end

  sig {
    params(
      conn: PG::Connection,
      osm_bz2: String,
    ).void
  }
  def self.export(conn, osm_bz2)
    sql = "
    SELECT
      *
    FROM
      osm_base
    ORDER BY
      CASE objtype WHEN 'n' THEN 1 WHEN 'w' THEN 2 ELSE 3 END,
      id
    "

    Bzip2::FFI::Writer.open(osm_bz2) { |f|
      f.write('<?xml version="1.0" encoding="UTF-8"?>')
      f.write("\n")
      f.write('<osm version="0.6" generator="clearance">')
      f.write("\n")

      conn.exec(sql) { |result|
        result.each{ |row|
          f.write(as_osm_xml(ObjectBase.from_hash(row)))
          f.write("\n")
        }
      }

      f.write('</osm>')
    }
  end

  sig {
    params(
      conn: PG::Connection,
      osc_gz: String,
    ).returns(T::Boolean)
  }
  def self.export_changes(conn, osc_gz)
    has_content = T.let(false, T::Boolean)
    Zlib::GzipWriter.open(osc_gz) { |f|
      f.write('<?xml version="1.0" encoding="UTF-8"?>')
      f.write("\n")
      f.write('<osmChange version="0.6" generator="clearance">')
      f.write("\n")

      sql = "
        SELECT
          *
        FROM
          osm_changes_applyed
        ORDER BY
          objtype,
          id,
          version
      "
      conn.exec(sql) { |result|
        action = ''
        action_old = ''
        result.each{ |row|
          has_content = true

          object = ObjectChanges.from_hash(row)
          action = if object.version == 1
                     'create'
                   elsif object.deleted
                     'delete'
                   else
                     'modify'
                   end

          if action_old != '' && action != action_old
            f.write("  </#{action_old}>\n")
          end
          if action_old != action
            f.write("  <#{action}>\n")
          end
          action_old = action

          f.write(as_osm_xml(object))
          f.write("\n")
        }
        f.write("  </#{action}>\n") if action != ''
      }

      f.write('</osmChange>')
    }

    if has_content
      conn.exec('DELETE FROM osm_changes_applyed')
    end

    has_content
  end

  sig {
    params(
      conn: PG::Connection,
      project: String,
    ).void
  }
  def self.export_update(conn, project)
    update_path = "/projects/#{project}/export/update"
    current_state_file = "#{update_path}/state.txt"

    state_file = StateFile::StateFile.from_file(current_state_file)
    sequence_number = state_file&.sequence_number || -1
    sequence_number += 1

    sequence_path = format('%09d', sequence_number)
    sequence_path0 = sequence_path[-3..]
    sequence_path1 = sequence_path[-6..-4]
    sequence_path2 = sequence_path[..-7]

    path = "#{update_path}/#{sequence_path2}/#{sequence_path1}"
    FileUtils.mkdir_p(path)
    osc_gz = "#{path}/#{sequence_path0}.osm.gz"

    has_content = export_changes(conn, osc_gz)

    if has_content
      osc_gz_state = osc_gz.gsub('.osm.gz', '.state.txt')
      StateFile::StateFile.new(
        timestamp: '2022-09-04T20:21:24Z',
        sequence_number: sequence_number
      ).save_to(osc_gz_state)
      FileUtils.copy(osc_gz_state, current_state_file)
    else
      # Nothing exported, remove files
      File.delete(osc_gz)
    end
  end
end
