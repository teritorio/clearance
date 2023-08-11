# frozen_string_literal: true
# typed: true

require './time_machine/overpasslike'

class OverpasslikeController < ApplicationController
  def interpreter
    project = params['project'].to_s
    data = params['data']

    Db::DbConnWrite.conn(project) { |conn|
      # Crud overpass extraction of tag selector of nwr line like
      # nrw[amenity=drinking_water][name](area.a);
      elements = data.split(';').select{ |line|
        line.strip.start_with?('nwr')
      }.map{ |nwr|
        nwr[(nwr.index('['))..(nwr.rindex(']'))]
      }.collect{ |selector|
        Overpasslike.query(conn, selector)
      }.flatten(1).uniq

      render json: {
        version: 0.6,
        generator: 'Clearance',
        osm3s: {
          dataset: project,
          copyright: 'The data included in this document is from www.openstreetmap.org. The data is made available under ODbL.'
        },
        elements: elements,
      }
    }
  end
end
