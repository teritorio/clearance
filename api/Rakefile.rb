# frozen_string_literal: true
# typed: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

require 'rake/testtask'

Rails.application.load_tasks

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['**/tests/**/*_test.rb']
  t.verbose = true
end
