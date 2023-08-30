# frozen_string_literal: true
# typed: true

require './lib/time_machine/overpasslike'

class OverpasslikeController < ApplicationController
  def interpreter
    project = T.let(params['project'].to_s, String)
    data = T.let(params['data'], String)

    Db::DbConnRead.conn(project) { |conn|
      area = /area\(([0-9]+)\)/.match(data)&.[](1)
      area_id = area.nil? ? nil : area.to_i - 3_600_000_000

      # Crud overpass extraction of tag selector of nwr line like
      # nrw[amenity=drinking_water][name](area.a);
      elements = data.split(';').select{ |line|
        line.strip.start_with?('nwr')
      }.map{ |nwr|
        nwr[(nwr.index('['))..(nwr.rindex(']'))]
      }.compact.collect{ |selector|
        Overpasslike.query(conn, selector, area_id)
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
