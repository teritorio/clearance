# frozen_string_literal: true
# typed: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"

  get ':project/changes_logs/', to: 'changes_logs#index'
end
