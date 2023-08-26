# frozen_string_literal: true
# typed: true

require './lib/time_machine/db'
require './lib/time_machine/changes_db'
require './lib/time_machine/configuration'

class ProjectsController < ApplicationController
  def index
    projects = Dir.glob('/projects/*/').to_h{ |project|
      c = ::Configuration.load("#{project}/config.yaml")
      date_start = StateFile::StateFile.from_file("#{project}/import/import.state.txt")
      date_last_update = StateFile::StateFile.from_file("#{project}/import/replication/state.txt")

      project = T.must(project.split('/')[-1])

      count = T.let(0, Integer)
      Db::DbConnRead.conn(project) { |conn|
        conn.exec('SELECT count(*) AS count FROM validations_log WHERE action IS NULL OR action = \'reject\'') { |result|
          count = result[0]['count'] || 0
        }
      }

      [project, {
        title: c.title,
        description: c.description,
        date_start: date_start&.timestamp,
        date_last_update: date_last_update&.timestamp,
        to_be_validated: count,
        user_groups: c.user_groups,
      }]
    }
    render json: projects
  end
end
