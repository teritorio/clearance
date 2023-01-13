# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module Watches
  extend T::Sig

  sig { params(watches: T::Hash[String, Types::Watch]).returns(T::Array[Types::OsmFiltersTags]) }
  def self.all_osm_filters_tags(watches)
    watches.values.collect(&:osm_filters_tags).flatten(1).compact
  end

  sig {
    params(
      filter_values: T.any(Types::OsmFilterValue, T::Array[Types::OsmFilterValue]),
      test_value: String,
    ).returns(T::Boolean)
  }
  def self.match_value(filter_values, test_value)
    filter_values = [filter_values] if !filter_values.is_a?(Array)

    !!(
      filter_values.include?(nil) ||
      filter_values.include?(test_value) ||
      filter_values.find{ |filter_value| filter_value.is_a?(Regexp) && filter_value.match(test_value) }
    )
  end

  sig {
    params(
      watches: T::Hash[String, Types::Watch],
      tags: T::Hash[String, String],
    ).returns(T::Array[String])
  }
  def self.match_osm_filters_tags(watches, tags)
    tags_keys = tags.keys
    watches.values.collect{ |watch|
      main_keys = watch.osm_filters_tags.collect{ |osm_filter_tag|
        osm_filter_tag.keys.intersection(tags_keys).select{ |key|
          match_value(osm_filter_tag[key], T.must(tags[key]))
        }
      }.flatten
      main_keys += (watch.osm_tags_extra&.intersection(tags_keys) || []) if !main_keys.empty?
      main_keys
    }.flatten.uniq
  end

  sig { params(filters: T::Array[Types::OsmFiltersTags]).returns(String) }
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
