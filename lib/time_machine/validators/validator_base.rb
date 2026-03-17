# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class ValidatorBase
    extend T::Sig

    sig {
      params(
        id: String,
        osm_tags_matches: Osm::TagsMatches,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, osm_tags_matches:, description: nil)
      @id = id
      @osm_tags_matches = osm_tags_matches
      @description = description
    end

    sig {
      returns(T::Hash[T.untyped, T.untyped])
    }
    def to_h
      instance_variables.select{ |v| [:@osm_tags_matches].exclude?(v) }.to_h { |v|
        [v.to_s.delete('@'), instance_variable_get(v)]
      }
    end
  end
end
