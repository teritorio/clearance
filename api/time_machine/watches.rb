# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './time_machine/osm_tags_filters'
require './time_machine/types'

module Watches
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
end
