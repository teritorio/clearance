# frozen_string_literal: true
# typed: true

require './lib/time_machine/db/db_conn'
require './lib/time_machine/osm/types'

class ChangesLogsController < ApplicationController
  extend T::Sig

  before_action :authenticate_user!, except: [:index]

  def index
    project = params['project'].to_s

    sql = 'SELECT * FROM changes_logs()'
    Db::DbConnRead.conn(project) { |conn|
      begin
        json = conn.exec(sql)
        render(json: json)
      rescue PG::UndefinedFunction
        render(status: :service_unavailable)
      end
    }
  end

  def sets
    project = params['project'].to_s

    config = ::Configuration.load("/projects/#{project}/config.yaml")
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

    locha_ids = T.let(params['_json'], T::Array[Integer])
    Db::DbConnWrite.conn(project) { |conn|
      Validation.accept_changes(conn, locha_ids, current_user_osm_id.to_i)
    }
  end
end
