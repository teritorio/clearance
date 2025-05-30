# frozen_string_literal: true
# typed: strict

class ApplicationController < ActionController::API
  extend T::Sig

  if ENV['SENTRY_DSN_TOOLS'].present?
    before_action :sentry_project_tag
  end

  delegate :osm_name, to: :current_user, prefix: true
  delegate :osm_id, to: :current_user, prefix: true

  rescue_from ActionController::ParameterMissing do |exception|
    render json: { error: exception.message }, status: :bad_request
  end

  rescue_from ActiveHash::RecordNotFound do |_exception|
    render nothing: true, status: :not_found
  end

  private

  sig { void }
  def sentry_project_tag
    project = params['project']
    Sentry.set_tags(project: project) if project
  end
end
