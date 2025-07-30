# frozen_string_literal: true
# typed: true

require './lib/time_machine/db/db_conn'
require './lib/time_machine/db/overpasslike'

class OverpasslikeController < ApplicationController
  def interpreter
    project = T.let(params['project'].to_s, String)
    data = T.cast(params.require(:data), String)

    begin
      Db::DbConnRead.conn(project) { |conn|
        elements = Db::Overpass.query(conn, data, 4326)
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
    rescue OverpassParserRuby::ParsingError => e
      puts e.inspect
      render status: :bad_request, html: "<html>
<body>
<p><strong style=\"color:#FF0000\">Error</strong>: #{e}</p>
</body>
</html>"
    end
  end
end
