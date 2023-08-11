# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module OsmTagsMatches
  extend T::Sig

  OsmMatchKey = T.type_alias { String }
  OsmMatchOperator = T.type_alias { T.any(NilClass, String) }
  OsmMatchValues = T.type_alias { T.any(NilClass, String, Regexp) }

  class OsmTagsMatch
    extend T::Sig

    sig {
      params(
        tags: String,
      ).void
    }
    def initialize(tags)
      throw 'Tags tags selector format' if tags.size <= 2

      a = T.must(tags[1..-2]).split('][').collect{ |osm_tag|
        k, o, v = osm_tag.split(/(=|~=|=~|!=|!~|~)/, 2).collect{ |s| unquote(s) }
        if o&.include?('~') && !v.nil?
          v = Regexp.new(v)
        end
        [T.must(k), [o, v]]
      }.group_by(&:first).transform_values{ |v| v.collect(&:last) }
      @tags_match = T.let(a, T::Hash[OsmMatchKey, T::Array[[OsmMatchOperator, OsmMatchValues]]])
    end

    sig {
      params(
        object_tags: T::Hash[String, String],
      ).returns(T::Array[[String, OsmTagsMatch]])
    }
    def match(object_tags)
      @tags_match.collect{ |key, op_values|
        value = object_tags[key]
        match = !value.nil? && op_values.all?{ |op, values|
          case op
          when nil then true
          when '=' then values == value
          when '!=' then values != value
          when '~' then T.cast(values, Regexp).match(value)
          when '!~' then !T.cast(values, Regexp).match(value)
          else throw "Not implemented operator #{op}"
          end
        }
        match ? [key, self] : nil
      }.compact
    end

    sig {
      params(
        escape_literal: T.proc.params(s: String).returns(String),
      ).returns(String)
    }
    def to_sql(escape_literal)
      p = @tags_match.collect { |key, op_values|
        key = escape_literal.call(key.to_s)
        op_values.collect{ |op, value|
          value = escape_literal.call(value.to_s) if !value.nil?
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

  class OsmTagsMatches
    extend T::Sig

    sig {
      params(
        matches: T::Array[OsmTagsMatch],
      ).void
    }
    def initialize(matches)
      @matches = matches
    end

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Array[[String, OsmTagsMatch]])
    }
    def match(tags)
      @matches.collect{ |watch|
        watch.match(tags)
      }.flatten(1)
    end

    sig {
      params(
        escape_literal: T.proc.params(s: String).returns(String),
      ).returns(String)
    }
    def to_sql(escape_literal)
      @matches.collect{ |match| match.to_sql(escape_literal) }.join(' OR ')
    end
  end
end
