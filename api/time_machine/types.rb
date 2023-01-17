# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/watches'

module Types
  extend T::Sig

  MultilingualString = T.type_alias { T::Hash[String, String] }

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
