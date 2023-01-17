# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/types'
require './time_machine/watches'

module Validators
  extend T::Sig

  class TagsChanges < ValidatorDual
    sig {
      params(
        id: String,
        watches: T::Hash[String, Types::Watch],
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, accept:, reject:, description: nil)
      super(id: id, watches: watches, accept: accept, reject: reject, description: description)
    end

    def apply(before, after, diff)
      match_keys = (
        (before && Watches.match_osm_filters_tags(@watches, before['tags']) || []) +
        Watches.match_osm_filters_tags(@watches, after['tags'])
      ).intersection(diff.tags.keys).select{ |tag|
        # Exclude new tags with insignificant value
        !before || !(before['tags'].exclude?(tag) && after['tags'].include?(tag) && after['tags'][tag] == 'no')
      }
      match_keys.each{ |key|
        assign_action_reject(diff.tags[key])
      }
      (diff.tags.keys - match_keys).each{ |key|
        assign_action_accept(diff.tags[key])
      }
    end
  end
end
