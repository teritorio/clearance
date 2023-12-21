# frozen_string_literal: true
# typed: strict

require 'test_helper'

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  test 'all' do
    get '/api/0.1/projects'
    assert_response :success
    response.parsed_body
  end
end
