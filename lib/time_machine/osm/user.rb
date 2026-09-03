# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'json'
require 'webcache'


module Osm
  extend T::Sig

  class User < T::InexactStruct
    const :id, Integer
    const :display_name, String
    const :account_created, String
    const :description, T.nilable(String)
    const :company, T.nilable(String)
    # <social-links>
    # 	<link platform="mastodon">https://mastodon.social/@jbpbis</link>
    # </social-links>
    # const :contributor-terms, T::Boolean
    const :img_href, T.nilable(String)
    # <roles><moderator/></roles>
    const :changesets_count, Integer
    const :traces_count, Integer
    const :blocks_received_count, T.nilable(Integer)
    const :blocks_received_active, T.nilable(Integer)
    # const :blocks_issued_count, T.nilable(Integer)
    # const :blocks_issued_active, T.nilable(Integer)
  end

  sig{
    params(
      ids: T::Array[Integer],
    ).returns(T::Array[User])
  }
  def self.fetch_users_by_ids(ids)
    cache = WebCache.new(dir: '/cache/users/', life: '1d')
    ids.uniq.sort.each_slice(100).flat_map{ |ids_batch|
      url = "https://www.openstreetmap.org/api/0.6/users.json?users=#{ids_batch.join(',')}"
      response = cache.get(url)
      raise [response.error, url].join(' ') if !response.success?

      JSON.parse(response.content)['users'].collect{ |json|
        json = json['user']
        json['changesets_count'] = json.dig('changesets', 'count')
        json['traces_count'] = json.dig('traces', 'count')
        json['blocks_received_count'] = json.dig('blocks', 'received', 'count')
        json['blocks_received_active'] = json.dig('blocks', 'received', 'active')
        User.from_hash(json, false)
      }
    }
  end
end
