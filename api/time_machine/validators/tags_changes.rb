# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/watches'

module Validators
  extend T::Sig

  class TagsChanges < ValidatorDual
    sig {
      params(
        id: String,
        watches: T.any(String, Watches::Watches),
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, accept:, reject:, description: nil)
      super(id: id, accept: accept, reject: reject, description: description)

      @watches = if watches.is_a?(Watches::Watches)
                   watches
                 else
                   Watches::Watches.new(YAML.unsafe_load_file(watches).transform_values{ |value|
                     Watches::Watch.new(
                       osm_filters_tags: value['osm_filters_tags'],
                       label: value['label'],
                       osm_tags_extra: value['osm_tags_extra'],
                     )
                   })
                 end
    end

    def apply(before, after, diff)
      match_keys = (
        (before && @watches.match(before['tags']) || []) +
        @watches.match(after['tags'])
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
