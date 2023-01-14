# frozen_string_literal: true
# typed: true


# class ValidatorsController < ApplicationController
class ValidatorsController < ActionController::API
  def index
    json = Config.load.validators.to_h{ |validator|
      h = validator.to_h
      [h['id'], h.except('id')]
    }
    render json: json
  end
end
