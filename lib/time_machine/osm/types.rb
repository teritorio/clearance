# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module Osm
  OsmKey = T.type_alias { String }
  OsmTags = T.type_alias { T::Hash[OsmKey, String] }

  class Changeset < T::InexactStruct
    const :id, Integer
    const :created_at, String
    const :closed_at, T.nilable(String)
    const :open, T::Boolean
    const :user, String
    const :uid, Integer
    const :minlat, T.nilable(T.any(Float, Integer))
    const :minlon, T.nilable(T.any(Float, Integer))
    const :maxlat, T.nilable(T.any(Float, Integer))
    const :maxlon, T.nilable(T.any(Float, Integer))
    const :comments_count, Integer
    const :changes_count, Integer
    const :created_count, T.nilable(Integer)
    const :modified_count, T.nilable(Integer)
    const :deleted_count, T.nilable(Integer)
    const :tags, T.nilable(T::Hash[String, String])
  end

  class OSMRelationMember < T::InexactStruct
    const :ref, Integer
    const :role, String
    const :type, String
  end

  OSMRelationMembers = T.type_alias { T::Array[OSMRelationMember] }

  class ObjectId < T::InexactStruct
    const :objtype, String
    const :id, Integer
    const :version, Integer
  end

  class ObjectBase < ObjectId
    const :changeset_id, Integer
    const :changeset, T.nilable(Changeset)
    const :created, Time
    const :uid, Integer
    const :username, T.nilable(String)
    const :tags, OsmTags
    const :lon, T.nilable(Float)
    const :lat, T.nilable(Float)
    const :nodes, T.nilable(T::Array[Integer])
    const :members, T.nilable(T::Array[OSMRelationMember])
  end

  class ObjectChangeId < ObjectId
    const :deleted, T::Boolean
  end

  class ObjectChanges < ObjectBase
    const :deleted, T::Boolean
  end
end
