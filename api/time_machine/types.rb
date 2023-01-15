# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

module Types
  extend T::Sig

  MultilingualString = T.type_alias { T::Hash[String, String] }

  OsmFilterKey = T.type_alias { String }
  OsmFilterValue = T.type_alias { T.any(NilClass, String, Regexp) }
  OsmFiltersTags = T.type_alias { T::Hash[OsmFilterKey, T.any(OsmFilterValue, T::Array[OsmFilterValue])] }

  class Watch < T::Struct
    const :label, T.nilable(MultilingualString)
    const :osm_filters_tags, T::Array[OsmFiltersTags]
    const :osm_tags_extra, T.nilable(T::Array[String])
  end

  # class ActionType < T::Enum
  #   enums do
  #     Accept = new
  #     Reject = new
  #   end
  # end

  ActionType = String

  class Action < T::Struct
    const :validator_id, String
    const :description, T.nilable(String)
    const :action, ActionType

    def inspect
      "<#{@validator_id}:#{@action}>"
    end

    def as_json
      [@validator_id, @action].as_json
    end
  end

  HashActions = T.type_alias { T::Hash[String, T::Array[Action]] }
end
