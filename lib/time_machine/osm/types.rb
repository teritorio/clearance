# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative '../osm/changeset'

module Osm
  OsmKey = T.type_alias { String }
  OsmTags = T.type_alias { T::Hash[OsmKey, String] }

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
