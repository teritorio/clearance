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
    cache = WebCache.new(dir: '/cache/changesets/', life: '1d')
    response = cache.get("https://www.openstreetmap.org/api/0.6/changeset/#{id}.json")
    return if !response.success?

    JSON.parse(response.content)['elements'][0].except('type')
  end
end
