# frozen_string_literal: true
# typed: true

require 'builder'
require './lib/time_machine/db/db_conn'
require './lib/time_machine/osm/types'
require './app/models/project'

class ChangesLogsController < ApplicationController
  extend T::Sig
  include ActionController::MimeResponds

  before_action :authenticate_user!, except: [:index]

  def index
    project = params['project'].to_s

    sql = 'SELECT * FROM changes_logs()'
    Db::DbConnRead.conn(project) { |conn|
      begin
        contents = conn.exec(sql)
        respond_to { |format|
          format.json {
            render(json: contents)
          }
          format.atom {
            public_url = ENV.fetch('PUBLIC_URL', nil)
            render plain: atom(project, Project.find(params['project']), contents, public_url)
          }
        }
      rescue PG::UndefinedFunction
        render(status: :service_unavailable)
      end
    }
  end

  def sets
    project = params['project'].to_s

    config = ::Configuration.load("/#{Project.projects_config_path}/#{project}/config.yaml")
    if config.nil?
      render(status: :not_found)
      return
    end

    user_in_project = config.main_contacts.include?(current_user_osm_name) || config.user_groups.any?{ |_key, user_group|
      user_group.users.include?(current_user_osm_name)
    }
    if !user_in_project
      render(status: :unauthorized)
      return
    end
    locha_ids = T.let(params['_json'], T.nilable(T::Array[Integer]))
    if locha_ids.nil?
      render(status: :bad_request)
      return
    end

    Db::DbConnWrite.conn(project) { |conn|
      Validation.accept_changes(conn, locha_ids, current_user_osm_id.to_i)
    }
  end

  private

  def atom(project, project_object, contents, public_url)
    xml = T.let(Builder::XmlMarkup.new, T.untyped) # Avoid typing error on builder
    xml.instruct!(:xml, version: '1.0')
    xml.feed(xmlns: 'http://www.w3.org/2005/Atom', 'xmlns:georss': 'http://www.georss.org/georss') {
      xml.title(project_object.title[I18n.locale.to_s] || project_object.title['en'] || project_object.first.value)
      xml.subtitle(project_object.description[I18n.locale.to_s] || project_object.description['en'] || project_object.first.value)
      xml.link(href: "#{public_url}/#{project}/changes_logs")
      xml.link(href: "#{public_url}/#{project}/changes_logs.atom", rel: 'self')
      xml.id("#{public_url}/#{project}/changes_logs")
      xml.updated(Time.now.utc.iso8601)
      contents.each { |content| atom_entry(xml, project, content, public_url) }
    }
    xml.target!
  end

  def atom_entry(xml, project, content, public_url)
    objects = content['objects']
    matches = objects.pluck('matches').flatten(1)
    xml.entry {
      xml.id("urn:lex:zz:#{content['id']}")
      xml.link(href: "#{public_url}/#{project}/changes_logs")

      dd = objects.collect{ |c|
        %w[base change].select{ |o| !c[o].nil? }.collect { |o|
          type = c.dig(o, 'objtype')
          id = c.dig(o, 'id')
          [
            "#{type}#{id}#{c.dig(o, 'deletes') ? ' (deleted)' : ''}",
            c.dig('change', 'tags', 'name'),
          ]
        }
      }.flatten(1)
      xml.content(type: 'xhtml') {
        xml.tag!('div', xmlns: 'http://www.w3.org/1999/xhtml') {
          xml.ul {
            dd.collect{ |a| a.compact.join(' - ') }.each { |line| xml.li(line) }
          }
        }
      }

      ids = dd.collect(&:first).compact_blank.uniq
      ids = (ids.size <= 2 ? ids : ids[0..2] + ['etc']).join(', ')
      names = dd.collect(&:last).compact_blank.uniq
      names = (names.size <= 2 ? names : names[0..2] + ['etc']).join(', ')

      title = matches.collect{ |m| m['name'] }.compact.collect{ |n|
        n[I18n.locale.to_s] || n['en'] || n.first.value
      }.uniq.join('/')
      xml.title([title, names, ids].compact_blank.join(' '))

      authors = objects.collect{ |c| [c.dig('base', 'username'), c.dig('change', 'username')] }.flatten.compact
      if authors.present?
        authors.uniq.each{ |a|
          xml.author {
            xml.name a
            xml.uri("https://www.openstreetmap.org/user/#{CGI.escape(a)}")
          }
        }
      end

      date = objects.collect{ |c| c.dig('change', 'created') }.max
      xml.updated("#{date}Z") if date.present?

      matches.collect{ |m| [m['sources'], m['user_groups']] }.flatten.uniq.each{ |category|
        xml.category(term: category)
      }

      xml.tag!('georss:point') { # Lat/Lon
        xml.text!("#{content['point_y']} #{content['point_x']}")
      }
    }
  end
end
