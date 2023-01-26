# frozen_string_literal: true
# typed: true

require './time_machine/db'

class ChangesLogsController < ApplicationController
  extend T::Sig

  def index
    project = params['project'].to_s

    sql = 'SELECT * FROM changes_logs()'
    Db::DbConnRead.conn(project) { |conn|
      json = conn.exec(sql).map{ |row|
        row['base'] = row['base']
        row['change'] =  row['change']
        row['diff_tags'] = row['diff_tags']
        row['diff_attribs'] = row['diff_attribs']
        row
      }
      render json: json
    }
  end

  def sets
    project = params['project'].to_s

    changes = ['_json'].map{ |change|
      Db::ObjectId.new(
        objtype: change['objtype'],
        id: change['id'],
        version: change['version'],
      )
    }

    Db::DbConnWrite.conn(project) { |conn|
      ChangesDb.accept_changes(conn, changes)
    }
  end
end
