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
        config: T.untyped,
        osm_tags_matches: Osm::TagsMatches,
        description: T.nilable(String),
      ).void
    }
    def initialize(id:, config:, osm_tags_matches:, description: nil)
      @id = id
      @config = config
      @osm_tags_matches = osm_tags_matches
      @description = description
    end

    sig {
      params(
        conn: T.nilable(PG::Connection),
        _proj: Integer,
        prevalidation_clusters: T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]],
      ).void
    }
    def apply(conn, _proj, prevalidation_clusters); end

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
