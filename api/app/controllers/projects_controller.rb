# frozen_string_literal: true
# typed: true


class ProjectsController < ApplicationController
  def index
    projects = Dir.glob('/projects/*/').to_h{ |project|
      c = Config.load("#{project}/config.yaml")
      date_start = StateFile::StateFile.from_file("#{project}/import/import.state.txt")
      date_last_update = StateFile::StateFile.from_file("#{project}/import/replication/state.txt")
      puts date_start.inspect, date_last_update.inspect
      [project.split('/')[-1], {
        description: c.description,
        date_start: date_start&.timestamp,
        date_last_update: date_last_update&.timestamp,
      }]
    }
    render json: projects
  end
end
