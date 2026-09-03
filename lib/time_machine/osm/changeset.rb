# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'json'
require 'webcache'


module Osm
  extend T::Sig

  class Changeset < T::InexactStruct
    const :id, Integer
    const :created_at, String
    const :closed_at, T.nilable(String)
    const :open, T::Boolean
    const :user, T.nilable(String)
    const :uid, T.nilable(Integer)
    const :min_lat, T.nilable(T.any(Float, Integer))
    const :min_lon, T.nilable(T.any(Float, Integer))
    const :max_lat, T.nilable(T.any(Float, Integer))
    const :max_lon, T.nilable(T.any(Float, Integer))
    const :comments_count, Integer
    const :changes_count, Integer
    const :created_count, T.nilable(Integer)
    const :modified_count, T.nilable(Integer)
    const :deleted_count, T.nilable(Integer)
    const :tags, T.nilable(T::Hash[String, String])
  end

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

      JSON.parse(response.content)['changesets'].collect{ |json|
        Changeset.from_hash(json, false)
      }
    }
  end
end
