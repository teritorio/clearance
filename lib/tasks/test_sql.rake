# frozen_string_literal: true
# typed: strict

require 'rake'

namespace :test do
  desc 'Test SQL script.'
  task :sql, [] => :environment do
    ['schema_geom_test.sql', 'schema_changes_geom_test.sql'].all? { |script|
      system("psql $DATABASE_URL -v ON_ERROR_STOP=ON -f ./test/lib/time_machine/sql/#{script}")
    } or exit 1
  end
end
