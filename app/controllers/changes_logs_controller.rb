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
        lochas = conn.exec(sql).collect{ |c| c['objects'] }
        respond_to { |format|
          format.json {
            render(json: lochas)
          }
          format.atom {
            public_url = ENV.fetch('PUBLIC_URL', nil)
            render plain: atom(project, Project.find(params['project']), lochas, public_url)
          }
        }
      rescue PG::UndefinedFunction
        render(status: :service_unavailable)
      end
    }
  end

  def accept_locha
    project = params['project'].to_s
    locha_id = params['locha_id'].to_i
    links_index = Integer(params['links_index'], exception: false)

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

    Db::DbConnWrite.conn(project) { |conn|
      Validation.accept_locha(conn, locha_id, links_index, current_user_osm_id.to_i)
    }
  end

  def accept_lochas
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
      Validation.accept_lochas(conn, locha_ids, current_user_osm_id.to_i)
    }
  end

  private

  sig { params(object: T::Hash[String, String], locale: T.untyped).returns(T.untyped) }
  def atom_i18n(object, locale)
    object[locale.to_s] || object['en'] || object.first&.last
  end

  def atom(project, project_object, lochas, public_url)
    xml = T.let(Builder::XmlMarkup.new, T.untyped) # Avoid typing error on builder
    xml.instruct!(:xml, version: '1.0')
    xml.feed(xmlns: 'http://www.w3.org/2005/Atom', 'xmlns:georss': 'http://www.georss.org/georss') {
      xml.title(atom_i18n(project_object.title, I18n.locale))
      xml.subtitle(atom_i18n(project_object.description, I18n.locale))
      xml.link(href: "#{public_url}/#{project}/changes_logs")
      xml.link(href: "#{public_url}/#{project}/changes_logs.atom", rel: 'self')
      xml.id("#{public_url}/#{project}/changes_logs")
      xml.updated(Time.now.utc.iso8601)
      href = "#{public_url}/#{project}/changes_logs"

      lochas.each { |locha|
        locha_id = locha['metadata']['locha_id']
        features = locha['features'].index_by { |f| f['id'] }
        links = locha['metadata']['links']

        objects = links.collect{ |link| (link.pluck('before') + link.pluck('after')).compact.uniq.collect{ |id| features[id] } }.flatten(1)
        matches = links.collect{ |link| link.pluck('matches').flatten(1) }.flatten(1)
        bbox = locha['bbox']
        point = "#{(bbox[0] + bbox[2]) / 2} #{(bbox[1] + bbox[3]) / 2}"
        atom_entry(xml, locha_id, objects, matches, point, href)
      }
    }
    xml.target!
  end

  def atom_entry(xml, locha_id, objects, matches, point, href)
    xml.entry {
      xml.id("urn:lex:zz:#{locha_id}")
      xml.link(href: href)

      dd = objects.collect{ |o|
        type = o['objtype']
        id = o['id']
        deleted = o.dig('properties', 'deleted') ? ' (deleted)' : ''
        [
          "#{type}#{id}#{deleted}",
          o.dig('properties', 'tags', 'name'),
        ]
      }
      xml.content(type: 'xhtml') {
        xml.tag!('div', xmlns: 'http://www.w3.org/1999/xhtml') {
          xml.ul {
            dd.collect{ |a| a.compact_blank.join(' - ') }.each { |line| xml.li(line) }
          }
        }
      }

      ids = dd.collect(&:first).compact_blank.collect{ |id| id[1..] }.uniq
      ids = (ids.size <= 2 ? ids : ids[0..2] + ['etc']).join(', ')
      names = dd.collect(&:last).compact_blank.uniq
      names = (names.size <= 2 ? names : names[0..2] + ['etc']).join(', ')

      title = matches.collect{ |m| m['name'] }.compact.collect{ |n| atom_i18n(n, I18n.locale) }.uniq.join('/')
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

      date = objects.collect{ |c| c.dig('change', 'created') }.compact.max
      xml.updated("#{date}Z") if date.present?

      matches.collect{ |m| [m['sources'], m['user_groups']] }.flatten.uniq.each{ |category|
        xml.category(term: category)
      }

      xml.tag!('georss:point') { # Lat/Lon
        xml.text!(point)
      }
    }
  end
end
