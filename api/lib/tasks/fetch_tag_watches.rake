# frozen_string_literal: true
# typed: true

require 'rake'
require 'json'
require 'yaml'
# require 'http'
require './time_machine/config'

def fetch_json(url)
  puts "Fetch... #{url}"
  resp = HTTP.follow.get(url)
  if !resp.status.success?
    raise [url, resp].inspect
  end

  JSON.parse(resp.body)
end

def merge_tag_watches(path)
  config = Config.load(path)
  config.customers.collect{ |_id, customer|
    customer.tag_watches
  }.collect{ |url|
    fetch_json(url).values
  }.flatten(1).each_with_object(Hash.new { Set.new }) { |elem, sum|
    elem['select'].each{ |select|
      sum[select] = sum[select].merge(elem['watch'] || [])
    }
  }.transform_values(&:to_a).collect{ |k, v|
    {
      'match' => k,
      'watch' => v.empty? ? nil : v
    }.compact
  }
end

namespace :config do
  desc 'Generate OSM tag watches config from remote datasource'
  task :fetch_tag_watches, [] => :environment do
    projects = ENV['project'] ? [ENV['project']] : Dir.glob('../projects/*/')
    projects.each{ |project|
      merged = merge_tag_watches("../projects/#{project}/config.yaml")
      File.write("../projects/#{project}/config-watches.yaml", YAML.dump(merged))
    }
  end
end
