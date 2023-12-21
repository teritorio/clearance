# frozen_string_literal: true
# typed: strict

require 'test_helper'

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  test 'me' do
    get '/api/0.1/users/me'
    assert_response 404
  end
end
