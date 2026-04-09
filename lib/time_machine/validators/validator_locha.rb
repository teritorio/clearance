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
  end
end
