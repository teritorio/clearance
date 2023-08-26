# frozen_string_literal: true
# typed: true

require './lib/time_machine/db'

class ChangesLogsController < ApplicationController
  extend T::Sig

  before_action :authenticate_user!, except: [:index]

  def index
    project = params['project'].to_s

    sql = 'SELECT * FROM changes_logs()'
    Db::DbConnRead.conn(project) { |conn|
      json = conn.exec(sql).map{ |row|
        row['base'] = row['base']
        row['change'] = row['change']
        row['matches'] = row['matches']
        row['diff_tags'] = row['diff_tags']
        row['diff_attribs'] = row['diff_attribs']
        row
      }
      render json: json
    }
  end

  def sets
    project = params['project'].to_s

    config = Configuration.load("/projects/#{project}/config.yaml")
    if config.nil?
      render(status: :not_found)
      return
    end

    user_in_project = config.user_groups.any?{ |_key, user_group|
      user_group.users.include?(current_user_osm_name)
    }
    if !user_in_project
      render(status: :unauthorized)
      return
    end

    changes = params['_json'].map{ |change|
      Db::ObjectChangeId.new(
        objtype: change['objtype'],
        id: change['id'],
        version: change['version'],
        deleted: change['deleted'],
      )
    }

    Db::DbConnWrite.conn(project) { |conn|
      ChangesDb.accept_changes(conn, changes)
    }
  end
end
