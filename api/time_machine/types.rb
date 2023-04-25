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
    const :options, T.nilable(T::Hash[String, T.untyped])

    sig {
      returns(String)
    }
    def inspect
      if @options
        "<#{@validator_id}:#{@action} (#{@options})>"
      else
        "<#{@validator_id}:#{@action}>"
      end
    end

    sig {
      params(
        json_options: T.untyped,
      ).returns(T::Array[T.untyped])
    }
    def as_json(json_options = T.unsafe(nil))
      [@validator_id, @action, @options].as_json(json_options)
    end
  end

  HashActions = T.type_alias { T::Hash[String, T::Array[Action]] }
end
