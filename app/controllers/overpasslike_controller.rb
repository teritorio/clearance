# frozen_string_literal: true
# typed: true

require './lib/time_machine/db/overpasslike'

class OverpasslikeController < ApplicationController
  def interpreter
    project = T.let(params['project'].to_s, String)
    data = T.let(params['data'], String)

    Db::DbConnRead.conn(project) { |conn|
      render json: {
        version: 0.6,
        generator: 'Clearance',
        osm3s: {
          dataset: project,
          copyright: 'The data included in this document is from www.openstreetmap.org. The data is made available under ODbL.'
        },
        elements: Db::Overpass.query(conn, data),
      }
    }
  end
end
