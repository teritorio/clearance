# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/osm/tags_matches'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class ValidatorBase
    extend T::Sig

    class Settings < T::Struct
      const :id, String
      const :config, T.untyped
      const :osm_tags_matches, Osm::TagsMatches
      const :description, T.nilable(String)
    end

    sig { returns(Settings) }
    attr_reader :settings

    sig {
      params(settings: Settings).void
    }
    def initialize(settings:)
      @settings = T.let(settings, Settings)
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
