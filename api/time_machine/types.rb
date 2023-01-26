# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

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
    extend T::Sig

    const :validator_id, String
    const :description, T.nilable(String)
    const :action, ActionType

    sig {
      returns(String)
    }
    def inspect
      "<#{@validator_id}:#{@action}>"
    end

    sig {
      params(
        options: T.untyped,
      ).returns(T::Array[T.untyped])
    }
    def as_json(options = T.unsafe(nil))
      [@validator_id, @action].as_json(options)
    end
  end

  HashActions = T.type_alias { T::Hash[String, T::Array[Action]] }
end
