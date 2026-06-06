# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './app/models/project'
require './lib/time_machine/osm/state_file'
require 'nokogiri'
require 'zlib'
require 'fileutils'
require 'osmium/osmium'

module Db
  extend T::Sig

  sig {
    params(
      result: T::Hash[String, T.untyped],
    ).returns(T::Hash[Symbol, String])
  }
  def self.attribs(result)
    {
      'version' => result['version'],
      'changeset' => result['changeset_id'],
      'uid' => result['uid'],
      'user' => result['username'],
      'timestamp' => result['created'].iso8601(0).gsub('+00:00', 'Z'),
    }
  end

  sig {
    params(
      conn: PG::Connection,
      project: String,
    ).void
  }
  def self.export(conn, project)
    projects_data_path = ENV['PROJECTS_DATA_PATH'].presence || 'projects_data'
    output_path = "#{projects_data_path}/#{project}/export/#{project}.osm.pbf"
    output_path_temp = "#{output_path}.tmp"
    FileUtils.rm_f(output_path_temp)

    writer = T.unsafe(Osmium::Writer).new(output_path_temp)

    state_file = T.must(Osm::StateFile.from_file("#{projects_data_path}/#{project}/export/update/state.txt"))
    writer.set_header('osmosis_replication_timestamp', state_file.timestamp)
    writer.set_header('osmosis_replication_sequence_number', state_file.sequence_number.to_s)
    public_url = ENV.fetch('PUBLIC_URL', nil)
    writer.set_header('osmosis_replication_base_url', "#{public_url}/api/0.1/#{project}/export/update/")

    conn.transaction {
      each_export_cursor_rows(conn, "
        SELECT id, version, changeset_id, created, uid, username, tags, lon, lat FROM osm_base_n ORDER BY id
      ", 'Nodes', 1_000_000, 'M') { |result|
        writer.add_node(result['id'], attribs(result), result['lat'], result['lon'], result['tags'])
      }

      each_export_cursor_rows(conn, "
        SELECT id, version, changeset_id, created, uid, username, tags, nodes FROM osm_base_w ORDER BY id
      ", 'Ways', 1_000_000, 'M') { |result|
        writer.add_way(result['id'], attribs(result), result['nodes'], result['tags'])
      }

      each_export_cursor_rows(conn, "
        SELECT id, version, changeset_id, created, uid, username, tags, members FROM osm_base_r ORDER BY id
      ", 'Relations', 10_000, 'k') { |result|
        writer.add_relation(result['id'], attribs(result), result['members'], result['tags'])
      }
    }

    writer.close

    FileUtils.mv(output_path_temp, output_path)
  end

  sig {
    params(
      conn: PG::Connection,
      sql: String,
      label: String,
      progress_every: Integer,
      progress_suffix: String,
      blk: T.proc.params(result: T.untyped).void,
    ).void
  }
  def self.each_export_cursor_rows(conn, sql, label, progress_every, progress_suffix, &blk)
    conn.exec("DECLARE my_cursor CURSOR FOR\n#{sql}")
    n = 0
    loop {
      n += 10_000
      puts "#{label}: #{n / progress_every}#{progress_suffix}..." if n % progress_every == 0

      results = conn.exec('FETCH 10000 FROM my_cursor')
      break if results.ntuples == 0

      results.each(&blk)
    }
    conn.exec('CLOSE my_cursor')
  end

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
          action = (
            if object.deleted
              'delete'
            elsif object.version == 1
              'create'
            else
              'modify'
            end
          )

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
    puts "Export changes to #{osc_gz}"

    has_content
  end

  sig {
    params(
      conn: PG::Connection,
      project: String,
    ).void
  }
  def self.export_update(conn, project)
    import_state_file = T.must(Osm::StateFile.from_file("/#{Project.projects_data_path}/#{project}/import/state.txt"))

    export_path = "/#{Project.projects_data_path}/#{project}/export/update"
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
