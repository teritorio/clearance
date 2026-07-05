# frozen_string_literal: true

module RuboCop
  module Cop
    module Custom
      class FromHashStrict < Base
        MSG = 'Do not use `from_hash` without a second (strict) argument; use `.new(**hash)` or `from_hash(hash, true)`.'
        RESTRICT_ON_SEND = [:from_hash].freeze

        def on_send(node)
          return if node.arguments.size >= 2

          add_offense(node.loc.selector)
        end
      end
    end
  end
end
