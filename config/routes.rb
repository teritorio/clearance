# frozen_string_literal: true
# typed: strict

Rails.application.routes.draw do
  get 'up' => 'rails/health#show'

  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }

  scope path: '/api/0.1' do
    # API
    get 'users/me', controller: 'users', action: 'me'

    scope path: '/projects' do
      get '/', controller: 'projects', action: 'index'
      scope path: '/:project' do
        # Data
        get '/', controller: 'projects', action: 'project'
        get '/changes_logs', controller: 'changes_logs', action: 'index'
        post '/changes_logs/accept', controller: 'changes_logs', action: 'sets'

        get '/validators/', to: 'validators#index'

        # Overpass like API
        get '/overpasslike', to: 'overpasslike#interpreter'
        get '/overpasslike/interpreter', to: 'overpasslike#interpreter'
        post '/overpasslike/interpreter', to: 'overpasslike#interpreter'
      end
    end
  end
end
