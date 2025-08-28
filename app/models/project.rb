# frozen_string_literal: true
# typed: true

require './lib/time_machine/configuration'
require './lib/time_machine/osm/state_file'
require './lib/time_machine/db/db_conn'
require 'active_hash'

class Project < ActiveFile::Base
  class << self
    def projects_config_path
      if ENV['RAILS_ENV'] == 'test'
        'projects_config_template'
      else
        ENV['PROJECTS_CONFIG_PATH'].presence || 'projects_config'
      end
    end

    def projects_data_path
      if ENV['RAILS_ENV'] == 'test'
        'projects_config_template'
      else
        ENV['PROJECTS_DATA_PATH'].presence || 'projects_data'
      end
    end

    def extension
      ''
    end

    def load_file
      Dir.glob('*/', base: "#{projects_config_path}/").collect{ |project|
        project = project[..-2]
        c = ::Configuration.load("#{projects_config_path}/#{project}/config.yaml")
        date_last_update = Osm::StateFile.from_file("#{projects_data_path}/#{project}/export/state.txt")

        {
          id: project,
          title: c.title,
          description: c.description,
          date_last_update: date_last_update&.timestamp,
          to_be_validated: count(project),
          main_contacts: c.main_contacts,
          user_groups: c.user_groups,
          project_tags: c.project_tags,
        }
      }
    end

    def count(project)
      count = T.let(nil, T.nilable(Integer))
      Db::DbConnRead.conn(project) { |conn|
        count = begin
          conn.exec('SELECT count(*) AS count FROM validations_log WHERE action IS NULL OR action = \'reject\'') { |result|
            result[0]['count'] || 0
          }
        rescue PG::UndefinedTable
          nil
        end
      }
      count
    end
  end
end
