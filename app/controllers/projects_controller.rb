# frozen_string_literal: true
# typed: true

require './lib/time_machine/osm/types'
require './lib/time_machine/osm/state_file'
require './lib/time_machine/db/db_conn'
require './lib/time_machine/validation/changes_db'
require './lib/time_machine/configuration'

class ProjectsController < ApplicationController
  def index
    Project.reload(true)
    render json: Project.all.collect(&:attributes).collect{ |project| prepare(project) }
  end

  def project
    Project.reload(true)
    render json: prepare(Project.find(params['project']).attributes)
  end

  private

  def prepare(project)
    project[:user_groups] = (project[:user_groups] || []).transform_values { |user_group|
      user_group.with(polygon: user_group.polygon.gsub(%r{^\./}, "/api/0.1/#{project[:id]}/"))
    }
    project
  end
end
