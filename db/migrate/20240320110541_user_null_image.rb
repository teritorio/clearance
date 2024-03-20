# frozen_string_literal: true
# typed: true

class UserNullImage < ActiveRecord::Migration[7.0]
  def change
    change_column_null :users, :osm_image_url, true
  end
end
