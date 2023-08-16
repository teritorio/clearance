# frozen_string_literal: true
# typed: strict

class ApplicationController < ActionController::API
  delegate :osm_name, to: :current_user, prefix: true
end
