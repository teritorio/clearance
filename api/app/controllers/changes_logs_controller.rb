# frozen_string_literal: true
# typed: true

class ChangesLogsController < ApplicationController
  def index
    sql = 'SELECT * FROM postgisftw.changes_logs()'
    Db::DbConn.conn{ |conn|
      json = conn.exec(sql).map{ |row|
        row['base'] = JSON.parse(row['base'])
        row['change'] = JSON.parse(row['change'])
        row['diff_tags'] = JSON.parse(row['diff_tags']) if row['diff_tags']
        row['diff_attribs'] = JSON.parse(row['diff_attribs']) if row['diff_attribs']
        row
      }
      render json: json
    }
  end

  def sets
    changes = params['_json'].map{ |change|
      Db::ObjectId.new(
        objtype: change['objtype'],
        id: change['id'],
        version: change['version'],
      )
    }
    ChangesDb.accept_changes(changes)
  end
end
