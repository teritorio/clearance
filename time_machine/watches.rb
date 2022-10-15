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
      p = filter.collect { |key, value|
        key = key.gsub("'", "\'")
        if value.nil?
          "tags?'#{key}'"
        elsif value.is_a?(String)
          value = value.to_s.gsub("'", "\'") if !value.nil?
          "tags?'#{key}' AND tags->>'#{key}' = '#{value}'"
        elsif value.is_a?(Regexp)
          value = value.to_s.gsub("'", "\'") if !value.nil?
          "tags?'#{key}' AND tags->>'#{key}' ~ '#{value}'"
        end
      }.join(' AND ')
      "(#{p})"
    }.join(' OR ')
  end
end
