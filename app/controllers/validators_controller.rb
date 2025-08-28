# frozen_string_literal: true
# typed: true

require './lib/time_machine/configuration'
require './app/models/project'


class ValidatorsController < ApplicationController
  def index
    project = params['project'].to_s

    json = ::Configuration.load("/#{Project.projects_config_path}/#{project}/config.yaml").validators.to_h{ |validator|
      h = validator.to_h
      [h['id'], h.except('id')]
    }
    render json: json
  end
end
