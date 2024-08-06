# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'json'
require 'webcache'


module Osm
  extend T::Sig

  sig{
    params(
      id: Integer,
    ).returns(T.nilable(Changeset))
  }
  def self.fetch_changeset_by_id(id)
    return nil if id == 0

    cache = WebCache.new(dir: '/cache/changesets/', life: '1d')
    url = "https://www.openstreetmap.org/api/0.6/changeset/#{id}.json"
    response = cache.get(url)
    raise [response.error, url].join(' ') if !response.success?

    JSON.parse(response.content)['elements'][0].except('type')
  end
end
