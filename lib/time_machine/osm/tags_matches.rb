# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative 'types'

module Osm
  extend T::Sig

  OsmMatchKey = T.type_alias { OsmKey }
  OsmMatchOperator = T.type_alias { T.any(NilClass, String) }
  OsmMatchValues = T.type_alias { T.any(NilClass, String, Regexp) }

  class TagsMatch
    extend T::Sig

    sig { returns(String) }
    attr_accessor :selector

    sig { returns(T.nilable(T::Array[String])) }
    attr_accessor :sources

    sig { returns(T::Array[String]) }
    attr_accessor :user_groups

    sig {
      params(
        selector: String,
        selector_extra: T.nilable(T::Hash[String, T.nilable(String)]),
        sources: T.nilable(T::Array[String]),
        user_groups: T::Array[String],
      ).void
    }
    def initialize(selector, selector_extra: nil, sources: nil, user_groups: [])
      throw 'Tags tags selector format' if selector.size <= 2

      a = T.must(selector[1..-2]).split('][').collect{ |osm_tag|
        k, o, v = osm_tag.split(/(=|~=|=~|!=|!~|~)/, 2).collect{ |s| unquote(s) }
        if o&.include?('~') && !v.nil?
          v = Regexp.new(v)
        end
        [T.must(k), [o, v]]
      }.group_by(&:first).transform_values{ |v| v.collect(&:last) }
      @selector_match = T.let(a, T::Hash[OsmMatchKey, T::Array[[OsmMatchOperator, OsmMatchValues]]])

      @selector = selector
      @selector_extra = selector_extra
      @sources = sources
      @user_groups = user_groups
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[OsmMatchKey, TagsMatch]])
    }
    def match(tags)
      ret = @selector_match.all?{ |key, op_values|
        value = tags[key]
        !value.nil? && op_values.all?{ |op, values|
          case op
          when nil then true
          when '=' then values == value
          when '!=' then values != value
          when '~' then T.cast(values, Regexp).match(value)
          when '!~' then !T.cast(values, Regexp).match(value)
          else throw "Not implemented operator #{op}"
          end
        }
      }
      ret ? @selector_match.collect{ |key, _op_values| [key, self] } : []
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[OsmMatchKey, TagsMatch]])
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
      p = @selector_match.collect { |key, op_values|
        key = escape_literal.call(key.to_s)
        op_values.collect{ |op, value|
          if !value.nil?
            value = value.to_s.gsub(/^\(\?-mix:/, '(') if value.is_a?(Regexp)
            value = escape_literal.call(value.to_s)
          end
          case op
          when nil then "tags?#{key}"
          when '=' then "(tags?#{key} AND tags->>#{key} = #{value})"
          when '!=' then "(NOT tags?#{key} OR tags->>#{key} != #{value})"
          when '~' then "(tags?#{key} AND tags->>#{key} ~ #{value})"
          when '!~' then "(NOT tags?#{key} OR tags->>#{key} !~ #{value})"
          else throw "Not implemented operator #{op}"
          end
        }
      }.join(' AND ')
      "(#{p})"
    end

    # Backport ruby 3.2
    sig {
      params(
        self_: String,
      ).returns(String)
    }
    def unquote(self_)
      s = self_.dup

      case self_[0, 1]
      when "'", '"', '`'
        s[0] = ''
      end

      case self_[-1, 1]
      when "'", '"', '`'
        s[-1] = ''
      end

      s
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
      ).returns(T::Array[[OsmMatchKey, TagsMatch]])
    }
    def match(tags)
      @matches.collect{ |watch|
        watch.match(tags)
      }.flatten(1)
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[OsmMatchKey, TagsMatch]])
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
