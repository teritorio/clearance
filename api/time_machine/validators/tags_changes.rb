# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/osm_tags_filters'

module Validators
  extend T::Sig

  class Watch < OsmTagsFilters::OsmTagsFilter
    sig {
      params(
        osm_filters_tags: T::Array[OsmTagsFilters::OsmFiltersTags],
        label: T.nilable(Types::MultilingualString),
        osm_tags_extra: T.nilable(T::Array[String]),
      ).void
    }
    def initialize(osm_filters_tags:, label: nil, osm_tags_extra: nil)
      super(osm_filters_tags)
      @label = label
      @osm_tags_extra = osm_tags_extra
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[String])
    }
    def match(tags)
      main_keys = super(tags)
      main_keys += (@osm_tags_extra&.intersection(tags.keys) || []) if !main_keys.empty?
      main_keys
    end
  end

  class Watches < OsmTagsFilters::OsmTagsFilters
  end

  class TagsChanges < ValidatorDual
    attr_reader :watches

    sig {
      params(
        id: String,
        watches: T.any(String, Watches),
        accept: String,
        reject: String,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, watches:, accept:, reject:, description: nil)
      super(id: id, accept: accept, reject: reject, description: description)

      @watches = if watches.is_a?(Watches)
                   watches
                 else
                   Watches.new(YAML.unsafe_load_file(watches).transform_values{ |value|
                     Watch.new(
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
