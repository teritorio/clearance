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

  OSMObject = T.type_alias {
    {
      'lat' => T.nilable(Float),
      'lon' => T.nilable(Float),
      'nodes' => T.nilable(T::Array[Integer]),
      'deleted' => T::Boolean,
      'members' => T.nilable(T::Array[Integer]),
      'version' => Integer,
      'changeset_id' => Integer,
      'uid' => Integer,
      'username' => String,
      'created' => String,
      'tags' => T::Hash[String, String],
    }
  }
end
