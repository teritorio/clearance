# frozen_string_literal: true
# typed: true

# class ChangesLogsController < ApplicationController
class ChangesLogsController < ActionController::API
  def index
    sql = 'SELECT * FROM postgisftw.changes_logs()'
    json = ActiveRecord::Base.connection.execute(sql).map{ |row|
      row['base'] = JSON.parse(row['base'])
      row['change'] = JSON.parse(row['change'])
      row['diff_tags'] = JSON.parse(row['diff_tags']) if row['diff_tags']
      row
    }
    render json:
  end
end
