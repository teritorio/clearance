# frozen_string_literal: true
# typed: true

require './lib/time_machine/osm/types'
require './lib/time_machine/osm/state_file'
require './lib/time_machine/db/db_conn'
require './lib/time_machine/validation/changes_db'
require './lib/time_machine/configuration'

class ProjectsController < ApplicationController
  def index
    render json: Project.all.collect(&:attributes)
  end

  def project
    render json: Project.find(params['project']).attributes
  end
end
