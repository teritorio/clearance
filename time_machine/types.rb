# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

module Types
  extend T::Sig

  MultilingualString = T.type_alias { T::Hash[String, String] }

  OsmFiltersTags = T.type_alias { T::Hash[String, T.any(NilClass, String, Regexp)] }

  class Watch < T::Struct
    const :label, T.nilable(MultilingualString)
    const :osm_filters_tags, T::Array[OsmFiltersTags]
    const :osm_tags_extra, T.nilable(T::Array[String])
  end

  class Config < T::Struct
    const :ontologie, Object
    const :watches, T::Hash[String, Watch]
    const :validators, T.nilable(T::Hash[String, T::Hash[String, Object]])
    const :customers, Object
  end
end
