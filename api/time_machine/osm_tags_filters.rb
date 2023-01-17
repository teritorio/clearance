# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module OsmTagsFilters
  extend T::Sig

  OsmFilterKey = T.type_alias { String }
  OsmFilterValue = T.type_alias { T.any(NilClass, String, Regexp) }
  OsmFiltersTags = T.type_alias { T::Hash[OsmFilterKey, T::Array[OsmFilterValue]] }

  class OsmTagsFilter
    extend T::Sig

    sig {
      params(
        osm_filters_tags: T::Array[T::Hash[OsmFilterKey, T.any(OsmFilterValue, T::Array[OsmFilterValue])]],
      ).void
    }
    def initialize(osm_filters_tags)
      f = T.cast(osm_filters_tags.each{ |osm_filter_tags|
        osm_filter_tags.transform_values! { |value|
          value.is_a?(Array) ? value : [value]
        }
      }, T::Array[OsmFiltersTags])
      @osm_filters_tags = T.let(f, T::Array[OsmFiltersTags])
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[String])
    }
    def match(tags)
      @osm_filters_tags.collect{ |osm_filter_tag|
        osm_filter_tag.keys.intersection(tags.keys).select{ |key|
          match_value(T.must(osm_filter_tag[key]), T.must(tags[key]))
        }
      }.flatten
    end

    sig {
      params(
        filter: T::Array[OsmFilterValue],
        test_value: String,
      ).returns(T::Boolean)
    }
    def match_value(filter, test_value)
      !!(filter.include?(nil) ||
        filter.include?(test_value) ||
        filter.find{ |f| f.is_a?(Regexp) && f.match(test_value) }
        )
    end

    sig { returns(String) }
    def to_sql
      @osm_filters_tags.collect{ |osm_filter_tags|
        p = osm_filter_tags.collect { |key, values|
          if values.include?(nil)
            "tags?'#{key}'"
          else
            v = values.collect{ |value|
              case value
              when String
                "tags->>'#{key}' = '#{value}'"
              when Regexp
                "tags->>'#{key}' ~ '#{value}'"
              end
            }
            "tags?'#{key}' AND (#{v.join(' OR ')})"
          end
        }.join(' AND ')
        "(#{p})"
      }.join(' OR ')
    end
  end

  class OsmTagsFilters
    extend T::Sig

    sig {
      params(
        filters: T::Hash[String, OsmTagsFilter],
      ).void
    }
    def initialize(filters)
      @filters = filters
    end

    # sig { returns(T::Array[Types::OsmFiltersTags]) }
    # def all_osm_filters_tags
    #   @filters.values.collect(&:osm_filters_tags).flatten(1).compact
    # end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[String])
    }
    def match(tags)
      @filters.values.collect{ |watch|
        watch.match(tags)
      }.flatten.uniq
    end

    sig { returns(String) }
    def to_sql
      @filters.values.collect(&:to_sql).join(' OR ')
    end
  end
end
