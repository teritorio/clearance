# frozen_string_literal: true
# typed: true

require './lib/time_machine/configuration'
require './lib/time_machine/osm/state_file'
require './lib/time_machine/db/db_conn'

class Project < ActiveFile::Base
  class << self
    def extension
      ''
    end

    def load_file
      Dir.glob('*', base: 'projects/').collect{ |project|
        c = ::Configuration.load("projects/#{project}/config.yaml")
        date_last_update = Osm::StateFile.from_file("projects/#{project}/export/state.txt")

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
