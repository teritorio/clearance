# frozen_string_literal: true
# typed: strict

Rails.application.routes.draw do
  # API

  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }
  get '/api/0.1/users/me', controller: 'users', action: 'me'

  # DATA

  get '/api/0.1/projects', controller: 'projects', action: 'index'

  get '/api/0.1/:project/changes_logs', controller: 'changes_logs', action: 'index'
  post '/api/0.1/:project/changes_logs/accept', controller: 'changes_logs', action: 'sets'

  get '/api/0.1/:project/validators/', to: 'validators#index'
end
