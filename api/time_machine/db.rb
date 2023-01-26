# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'pg'
require './time_machine/types'
require 'json'
require 'nokogiri'
require 'zlib'
require 'fileutils'

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
      timestamp: object.created,
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
      osm_xml: String,
    ).void
  }
  def self.export(conn, osm_xml)
    sql = "
    SELECT
      *
    FROM
      osm_base
    ORDER BY
      objtype,
      id
    "

    File.open(osm_xml, 'w') { |f|
      f.write('<?xml version="1.0" encoding="UTF-8"?>')
      f.write("\n")
      f.write('<osm version="0.6" generator="a-priori-validation-for-osm">')
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
    ).void
  }
  def self.export_changes(conn, osc_gz)
    Zlib::GzipWriter.open(osc_gz) { |f|
      f.write('<?xml version="1.0" encoding="UTF-8"?>')
      f.write("\n")
      f.write('<osmChange version="0.6" generator="a-priori-validation-for-osm">')
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

    conn.exec('DELETE FROM osm_changes_applyed')
  end

  sig {
    params(
      conn: PG::Connection,
      update_path: String,
    ).void
  }
  def self.export_update(conn, update_path)
    current_state_file = "#{update_path}/state.txt"

    sequence_number = -1
    if File.exist?(current_state_file)
      s = File.readlines(current_state_file).find{ |line| line.start_with?('sequenceNumber=') }
      if s
        sequence_number = s.split('=')[1].to_i
      end
    end

    sequence_number += 1

    sequence_path = format('%09d', sequence_number)
    sequence_path0 = sequence_path[-3..]
    sequence_path1 = sequence_path[-6..-4]
    sequence_path2 = sequence_path[..-7]

    path = "#{update_path}/#{sequence_path2}/#{sequence_path1}"
    FileUtils.mkdir_p(path)
    osc_gz = "#{path}/#{sequence_path0}.osm.gz"

    export_changes(conn, osc_gz)

    osc_gz_state = osc_gz.gsub('.osm.gz', '.state.txt')
    File.write(osc_gz_state, "#
timestamp=2022-09-04T20:21:24Z
sequenceNumber=#{sequence_number}
")
    FileUtils.copy(osc_gz_state, current_state_file)
  end
end
