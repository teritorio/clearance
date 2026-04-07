# frozen_string_literal: true
# typed: true

require 'rake'
require 'json'
require 'http'
require 'sentry-ruby'
require 'json-schema'


if ENV['SENTRY_DSN_TOOLS'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN_TOOLS']
    # enable performance monitoring
    config.traces_sample_rate = 1
    # get breadcrumbs from logs
    config.breadcrumbs_logger = [:http_logger]
  end
end

def fetch_json(url)
  puts url.inspect
  JSON.parse(HTTP.follow.get(url))
end

def schema_for(path)
  path = path.gsub('/', '~1')
  "#/paths/#{path}/get/responses/200/content/application~1json/schema"
end

def fully_validate?(schema, json, name, fragment: nil)
  errors = JSON::Validator.fully_validate(schema, json, fragment: fragment)
  if errors.empty?
    puts "#{name} [valid]"
    true
  else
    errors.each{ |error|
      keys = error.match(/'(#[^']*)'/)[1][2..].split('/')
      begin
        keys = keys[..2].collect{ |k| Integer(k, exception: false) || k }
        puts "#{name} #{error} #{json.dig(*keys).to_json}"
      rescue StandardError
        puts "#{name} #{error}"
      end
    }
    puts "#{name} [#{errors.size} errors]"
    false
  end
end

def validate_schema(url_base)
  schema = YAML.safe_load_file('public/openapi-0.1.yaml')
  projects = fetch_json("#{url_base}/api/0.1/projects/")
  fully_validate?(schema, projects, '/api/0.1/projects/', fragment: schema_for('/api/0.1/projects/'))
  projects.select{ |project|
    !project['date_last_update'].nil? && !project['to_be_validated'].nil?
    # project['id'] == 'france_la_reunion_poi'
  }.each{ |project|
    fully_validate?(schema, fetch_json("#{url_base}/api/0.1/projects/#{project['id']}/changes_logs"), "/api/0.1/projects/#{project['id']}/changes_logs", fragment: schema_for('/api/0.1/projects/{project}/changes_logs'))
  }
end

namespace :api01 do
  desc 'Validate API JSON with Swagger Schema'
  task :validate, [] => :environment do
    url_base, = ARGV[2..]
    validate_schema(url_base)
    exit 0 # Beacause of manually deal with rake command line arguments
  end
end
