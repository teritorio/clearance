# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

module Types
  extend T::Sig

  class Config < T::Struct
    const :ontologie, Object
    const :sources, Object
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
