# frozen_string_literal: true
# typed: strict

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
