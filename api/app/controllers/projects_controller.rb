# frozen_string_literal: true
# typed: true


class ProjectsController < ApplicationController
  def index
    projects = Dir.glob('/projects/*/').to_h{ |project|
      c = Config.load("#{project}/config.yaml")
      [project.split('/')[-1], { description: c.description }]
    }
    render json: projects
  end
end
