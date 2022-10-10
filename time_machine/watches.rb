# frozen_string_literal: true
# typed: true

require './types'


module  Watches
  include Types
  extend T::Sig

  sig { params(watches: T::Hash[String, Watch]).returns(T::Array[OsmFiltersTags]) }
  def self.all_osm_filters_tags(watches)
    watches.values.collect(&:osm_filters_tags).flatten(1).compact
  end

  sig { params(filters: T::Array[OsmFiltersTags]).returns(String) }
  def self.osm_filters_tags_to_sql(filters)
    filters.collect { |filter|
      '(' + filter.collect { |key, value|
        key = key.gsub("'", "\'")
        value = value.to_s.gsub("'", "\'") if !value.nil?
        if value.nil?
          "tags?'#{key}'"
        elsif value.is_a?(String)
          "tags?'#{key}' AND tags->>'#{key}' = '#{value}'"
        else
          "tags?'#{key}' AND tags->>'#{key}' ~ '#{value}'"
        end
      }.join(' AND ') + ')'
    }.join(' OR ')
  end
end
