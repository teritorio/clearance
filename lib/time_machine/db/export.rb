# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/osm/state_file'
require 'nokogiri'
require 'zlib'
require 'fileutils'
require 'bzip2/ffi'

module Db
  extend T::Sig

  sig {
    params(
      object: Osm::ObjectBase,
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
      tags: Osm::OsmTags,
    ).void
  }
  def self.as_osm_xml_tags(xml, tags)
    tags.each{ |k, v|
      xml.tag(k: k, v: v)
    }
  end

  sig {
    params(
      object: Osm::ObjectBase,
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
    sql = "(
    SELECT
      'n' AS objtype,
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
      NULL::jsonb AS members
    FROM
      osm_base_n
    ORDER BY
      id

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
      NULL::jsonb AS members
    FROM
      osm_base_w
    ORDER BY
      id

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
      members
    FROM
      osm_base_r
    ORDER BY
      id
    )"

    Bzip2::FFI::Writer.open(osm_bz2) { |f|
      f.write('<?xml version="1.0" encoding="UTF-8"?>')
      f.write("\n")
      f.write('<osm version="0.6" generator="clearance">')
      f.write("\n")

      conn.transaction {
        conn.exec("DECLARE my_cursor CURSOR FOR #{sql}")
        loop {
          result = conn.exec('FETCH 1000 FROM my_cursor')
          break if result.ntuples == 0

          result.each { |row|
            f.write(as_osm_xml(Osm::ObjectBase.from_hash(row)))
            f.write("\n")
          }
        }

        conn.exec('CLOSE my_cursor')
      }

      f.write('</osm>')
    }
  end

  sig {
    params(
      conn: PG::Connection,
      table: String,
      osc_gz: String,
    ).returns(T::Boolean)
  }
  def self.export_changes(conn, table, osc_gz)
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
          #{table}
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

          object = Osm::ObjectChanges.from_hash(row)
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

    has_content
  end

  sig {
    params(
      conn: PG::Connection,
      project: String,
    ).void
  }
  def self.export_update(conn, project)
    import_state_file = T.must(Osm::StateFile.from_file("/projects/#{project}/import/state.txt"))

    export_path = "/projects/#{project}/export/update"
    export_state_file_path = "#{export_path}/state.txt"
    export_state_file = Osm::StateFile.from_file(export_state_file_path)

    sequence_number = export_state_file&.sequence_number || 0
    sequence_number += 1

    sequence_path = format('%09d', sequence_number)
    sequence_path0 = sequence_path[-3..]
    sequence_path1 = sequence_path[-6..-4]
    sequence_path2 = sequence_path[..-7]

    path = "#{export_path}/#{sequence_path2}/#{sequence_path1}"
    FileUtils.mkdir_p(path)
    osc_gz = "#{path}/#{sequence_path0}.osc.gz"

    has_content = export_changes(conn, 'osm_changes_applyed', osc_gz)

    if has_content
      conn.exec('DELETE FROM osm_changes_applyed')

      osc_gz_state = osc_gz.gsub('.osc.gz', '.state.txt')
      Osm::StateFile.new(
        timestamp: import_state_file.timestamp,
        sequence_number: sequence_number
      ).save_to(osc_gz_state)
      FileUtils.copy(osc_gz_state, export_state_file_path)
    else
      # Nothing exported, remove files
      File.delete(osc_gz)
    end
  end

  sig {
    params(
      conn: PG::Connection,
      osc_gz: String,
    ).void
  }
  def self.export_retained_diff(conn, osc_gz)
    export_changes(conn, 'osm_changes', osc_gz)
  end
end
