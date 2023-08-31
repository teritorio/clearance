# frozen_string_literal: true
# typed: strict

require 'rake'

namespace :test do
  desc 'Test SQL script.'
  task :sql, [] => :environment do
    Dir['./test/lib/time_machine/sql/**/*.sql'].all? { |script|
      puts "\n======== #{script} ========\n"
      system("psql $DATABASE_URL -v ON_ERROR_STOP=ON -f #{script}")
    } or exit 1
  end
end
