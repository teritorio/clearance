# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'test/unit'
require './types'
require './watches'


class TestWatches < Test::Unit::TestCase
  extend T::Sig
  include Types
  include Watches

  def test_all_osm_filters_tags
    watches = {
      amenity: Watch.new(
        osm_filters_tags: [{ 'amenity' => /.*/ }],
      ),
      florist: Watch.new(
        osm_filters_tags: [{ 'shop' => 'florist' }]
      ),
    }

    filters = Watches.all_osm_filters_tags(watches)

    assert_equal(2, filters.size)
  end

  def test_osm_filters_tags_to_sql
    watches = {
      amenity: Watch.new(
        osm_filters_tags: [{ 'amenity' => nil }],
      ),
      florist: Watch.new(
        osm_filters_tags: [{ 'shop' => 'florist' }]
      ),
    }

    filters = Watches.all_osm_filters_tags(watches)
    sql = Watches.osm_filters_tags_to_sql(filters)

    assert_equal("(tags?'amenity') OR (tags?'shop' AND tags->>'shop' = 'florist')", sql)
  end
end
