# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'


module LogicalHistory
  module Refs
    extend T::Sig

    sig {
      params(
        tags: T::Hash[String, String],
      ).returns(T::Hash[String, String])
    }
    def self.refs(tags)
      tags.select{ |k, _v| k == 'ref' || k.start_with?('ref:') }
    end
  end
end
