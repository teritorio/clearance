# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_base'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class ValidatorLocha < ValidatorBase
    extend T::Sig

    sig {
      params(
        conn: T.nilable(PG::Connection),
        proj: Integer,
        prevalidation_clusters: T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]],
      ).void
    }
    def apply(conn, proj, prevalidation_clusters); end
  end
end
