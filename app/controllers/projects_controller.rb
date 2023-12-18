# frozen_string_literal: true
# typed: true

require './lib/time_machine/osm/types'
require './lib/time_machine/osm/state_file'
require './lib/time_machine/db/db_conn'
require './lib/time_machine/validation/changes_db'
require './lib/time_machine/configuration'

class ProjectsController < ApplicationController
  def index
    projects = Dir.glob('*', base: '/projects/').index_with{ |project|
      get_project(project)
    }
    render json: projects
  end

  def project
    project = params['project'].to_s.gsub('/', '')
    render json: get_project(project)
  end

  private

  def get_project(project)
    c = ::Configuration.load("/projects/#{project}/config.yaml")
    date_last_update = Osm::StateFile.from_file("/projects/#{project}/import/replication/state.txt")

    project = T.must(project.split('/')[-1])

    count = T.let(0, Integer)
    Db::DbConnRead.conn(project) { |conn|
      conn.exec('SELECT count(*) AS count FROM validations_log WHERE action IS NULL OR action = \'reject\'') { |result|
        count = result[0]['count'] || 0
      }
    }

    {
      slug: project,
      title: c.title,
      description: c.description,
      date_last_update: date_last_update&.timestamp,
      to_be_validated: count,
      main_contacts: c.main_contacts,
      user_groups: c.user_groups,
      project_tags: c.project_tags,
    }
  end
end
