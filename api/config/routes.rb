# frozen_string_literal: true
# typed: strict

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"

  get '/:project/changes_logs', controller: 'changes_logs', action: 'index'
  post '/:project/changes_logs/accept', controller: 'changes_logs', action: 'sets'

  get '/:project/validators/', to: 'validators#index'
end
