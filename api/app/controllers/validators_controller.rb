# frozen_string_literal: true
# typed: true


# class ValidatorsController < ApplicationController
class ValidatorsController < ActionController::API
  def index
    json = Config.load.validators.transform_values{ |validator|
      puts validator
      validator.to_h.except('instance')
    }
    render json: json
  end
end
