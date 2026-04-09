# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_locha'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class ValidatorLochaSql < ValidatorLocha
    extend T::Sig

    sig {
      params(
        conn: PG::Connection,
        proj: Integer,
      ).void
    }
    def pre_compute_sql(conn, proj); end
  end
end
