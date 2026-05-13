# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'json'
require 'webcache'


module Osm
  extend T::Sig

  sig{
    params(
      ids: T::Array[Integer],
    ).returns(T::Array[Changeset])
  }
  def self.fetch_changeset_by_ids(ids)
    cache = WebCache.new(dir: '/cache/changesets/', life: '1d')
    ids.uniq.sort.each_slice(100).flat_map{ |ids_batch|
      url = "https://www.openstreetmap.org/api/0.6/changesets.json?changesets=#{ids_batch.join(',')}"
      response = cache.get(url)
      raise [response.error, url].join(' ') if !response.success?

      JSON.parse(response.content)['changesets']
    }
  end
end
