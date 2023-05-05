# frozen_string_literal: true
# typed: strict

class UsersController < ApplicationController
  def me
    render json: current_user
  end
end
