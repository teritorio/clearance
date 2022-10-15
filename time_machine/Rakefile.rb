# frozen_string_literal: true
# typed: true

require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['tests/**/*_test.rb']
  t.verbose = true
end
