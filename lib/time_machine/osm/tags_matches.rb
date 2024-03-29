# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative 'types'
require 'overpass_parser/visitor'


module Osm
  extend T::Sig

  OsmMatchKey = T.type_alias { OsmKey }
  OsmMatchOperator = T.type_alias { T.any(NilClass, String) }
  OsmMatchValues = T.type_alias { T.any(NilClass, String, Regexp) }

  OsmQuerySelector = T.type_alias { OsmKey }

  class TagsMatch
    extend T::Sig

    sig { returns(T.nilable(T::Array[String])) }
    attr_accessor :sources

    sig { returns(T::Array[String]) }
    attr_accessor :user_groups

    sig { returns(T.nilable(T::Hash[String, String])) }
    attr_accessor :name

    sig { returns(T.nilable(String)) }
    attr_accessor :icon

    sig {
      params(
        selectors: T::Array[T.any(String, OverpassParser::Selectors)],
        selector_extra: T.nilable(T::Hash[String, T.nilable(String)]),
        sources: T.nilable(T::Array[String]),
        user_groups: T::Array[String],
        name: T.nilable(T::Hash[String, String]),
        icon: T.nilable(String),
      ).void
    }
    def initialize(selectors, selector_extra: nil, sources: nil, user_groups: [], name: nil, icon: nil)
      @selector_matches = T.let(selectors.collect{ |selector|
        if selector.is_a?(String)
          throw 'Tags selector format' if selector.size <= 2

          tree = OverpassParser.tree("node#{selector};")
          tree[0][:queries][0][:selectors]
        else
          selector
        end
      }, T::Array[OverpassParser::Selectors])

      @selector_extra = selector_extra
      @name = name
      @icon = icon

      # Ensure key from selectors are in selector_extra
      selectors_keys = @selector_matches.collect{ |s| s.collect(&:key) }.flatten.uniq.filter{ |key| @selector_extra.nil? || !@selector_extra.key?(key) }
      if @selector_extra.nil?
        @selector_extra = selectors_keys.index_with{ |_key| nil }
      else
        selectors_keys.each{ |key|
          if !@selector_extra.key?(key)
            @selector_extra[key] = nil
          end
        }
      end

      @sources = sources
      @user_groups = user_groups
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[OsmQuerySelector, TagsMatch]])
    }
    def match(tags)
      @selector_matches.collect{ |selectors|
        m = selectors.matches(tags)
        [selectors.sort.to_overpass, self] if !m.nil?
      }.compact
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[OsmQuerySelector, TagsMatch]])
    }
    def match_with_extra(tags)
      main_keys = match(tags)
      main_keys += (@selector_extra&.keys&.intersection(tags.keys) || []).collect{ |key| [key, self] } if !main_keys.empty?
      main_keys
    end

    sig {
      params(
        escape_literal: T.proc.params(s: String).returns(String),
      ).returns(String)
    }
    def to_sql(escape_literal)
      pp = @selector_matches.collect{ |selectors|
        p = selectors.to_sql(escape_literal)
        "(#{p})"
      }
      pp.size == 1 ? T.must(pp[0]) : "(#{pp.join(' OR ')})"
    end
  end

  class TagsMatches
    extend T::Sig

    sig {
      params(
        matches: T::Array[TagsMatch],
      ).void
    }
    def initialize(matches)
      @matches = matches
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[OsmQuerySelector, TagsMatch]])
    }
    def match(tags)
      @matches.collect{ |watch|
        watch.match(tags)
      }.flatten(1)
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[OsmQuerySelector, TagsMatch]])
    }
    def match_with_extra(tags)
      @matches.collect{ |watch|
        watch.match_with_extra(tags)
      }.flatten(1)
    end

    sig {
      params(
        escape_literal: T.proc.params(s: String).returns(String),
      ).returns(String)
    }
    def to_sql(escape_literal)
      if @matches.blank?
        'true'
      else
        @matches.collect{ |match| match.to_sql(escape_literal) }.join(' OR ')
      end
    end
  end
end
