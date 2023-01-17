# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require './time_machine/types'
require 'active_support'
require 'active_support/core_ext'

module Validators
  extend T::Sig

  class Deleted < Validator
    def apply(_before, after, diff)
      return if !after['deleted']

      diff.attribs.each { |_key, action|
        assign_action(action)
      }
      diff.tags.each { |_key, action|
        assign_action(action)
      }
    end
  end
end
