# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '>= 3.4'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'activemodel'
gem 'activerecord'
gem 'activesupport'
gem 'rails', '~> 8.0.0'

# Use the Puma web server [https://github.com/puma/puma]
gem 'puma', '~> 6.6'

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors'

gem 'tzinfo-data'

gem 'active_hash', '~> 2.3.0'
gem 'bzip2-ffi'
gem 'devise'
gem 'http'
gem 'json'
gem 'levenshtein-ffi'
gem 'nokogiri'
gem 'omniauth'
gem 'omniauth-osm-oauth2'
gem 'omniauth-rails_csrf_protection'
gem 'optparse'
gem 'overpass_parser_ruby', git: 'https://github.com/teritorio/overpass_parser_ruby.git'
gem 'pg', '~> 1.1'
gem 'rego'
gem 'rgeo-geojson'
gem 'rgeo-proj4'
gem 'sentry-rails'
gem 'sentry-ruby'
gem 'sorbet-runtime'
gem 'webcache'
gem 'yaml_extend'

group :development do
  gem 'rake'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rake', require: false
  gem 'ruby-lsp', require: false
  gem 'sorbet', require: false
  # gem 'sorbet-rails', require: false # Doest nor work with tapioca 0.17.0
  gem 'tapioca', require: false
  gem 'test-unit'

  # Only for sorbet typechecker
  gem 'psych'
  gem 'racc'
  gem 'rbi'

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'byebug'
  gem 'debug', platforms: %i[mri mingw x64_mingw]

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

gem 'builder', '~> 3.3'
