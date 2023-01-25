# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module OsmTagsMatchs
  extend T::Sig

  OsmMatchKey = T.type_alias { String }
  OsmMatchValues = T.type_alias { T.any(NilClass, String, Regexp) }

  class OsmTagsMatch
    extend T::Sig

    sig {
      params(
        tags: T::Hash[OsmMatchKey, T.any(OsmMatchValues, T::Array[OsmMatchValues])],
      ).void
    }
    def initialize(tags)
      a = tags.transform_values! { |value|
        value.is_a?(Array) ? value : [value]
      }
      @tags_match = T.let(a, T::Hash[OsmMatchKey, T::Array[OsmMatchValues]])
    end

    sig {
      params(
        match: T::Array[OsmMatchValues],
        object_tags: String,
      ).returns(T::Boolean)
    }
    def match_value(match, object_tags)
      !!(match.include?(nil) ||
        match.include?(object_tags) ||
        match.find{ |f| f.is_a?(Regexp) && f.match(object_tags) }
        )
    end

    sig {
      params(
        object_tags: T::Hash[String, String],
      ).returns(T::Array[String])
    }
    def match(object_tags)
      @tags_match.keys.intersection(object_tags.keys).select{ |key|
        match_value(T.must(@tags_match[key]), T.must(object_tags[key]))
      }
    end

    sig { returns(String) }
    def to_sql
      p = @tags_match.collect { |key, values|
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
    end
  end

  class OsmTagsMatchSet
    extend T::Sig

    sig {
      params(
        tags_set: T::Array[OsmTagsMatch],
      ).void
    }
    def initialize(tags_set)
      @tags_set = tags_set
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[String])
    }
    def match(tags)
      @tags_set.collect{ |tags_to_match|
        tags_to_match.match(tags)
      }.flatten
    end

    sig { returns(String) }
    def to_sql
      @tags_set.collect(&:to_sql).join(' OR ')
    end
  end

  class OsmTagsMatchs
    extend T::Sig

    sig {
      params(
        matches: T::Hash[String, OsmTagsMatchSet],
      ).void
    }
    def initialize(matches)
      @matches = matches
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[String])
    }
    def match(tags)
      @matches.values.collect{ |watch|
        watch.match(tags)
      }.flatten.uniq
    end

    sig { returns(String) }
    def to_sql
      @matches.values.collect(&:to_sql).join(' OR ')
    end
  end
end
