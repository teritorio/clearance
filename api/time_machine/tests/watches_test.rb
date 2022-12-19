# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'test/unit'
require './time_machine/types'
require './time_machine/watches'


class TestWatches < Test::Unit::TestCase
  extend T::Sig
  include Types
  include Watches

  def test_all_osm_filters_tags
    watches = T.let({
      amenity: Watch.new(
        osm_filters_tags: [{ 'amenity' => /.*/ }],
      ),
      florist: Watch.new(
        osm_filters_tags: [{ 'shop' => 'florist' }]
      ),
    }, T::Hash[String, Types::Watch])

    filters = Watches.all_osm_filters_tags(watches)

    assert_equal(2, filters.size)
  end

  def test_match_value
    assert_true(Watches.match_value([nil], '+48'))

    assert_true(Watches.match_value(['+48'], '+48'))
    assert_false(Watches.match_value(['+48'], '+4'))

    assert_true(Watches.match_value([/4/], '+48'))
    assert_false(Watches.match_value([/5/], '+48'))
  end

  def test_match_osm_filters_tags
    watches = T.let({
      amenity: Watch.new(
        osm_filters_tags: [{ 'amenity' => /.*/ }],
        osm_tags_extra: ['phone'],
      ),
      florist: Watch.new(
        osm_filters_tags: [{ 'shop' => 'florist' }],
        osm_tags_extra: %w[phone fax],
      ),
    }, T::Hash[String, Watch])

    assert_equal(['shop'], Watches.match_osm_filters_tags(watches, { 'shop' => 'florist' }))
    assert_equal([], Watches.match_osm_filters_tags(watches, { 'shop' => 'fish' }))
    assert_equal(%w[phone shop].sort, Watches.match_osm_filters_tags(watches, { 'shop' => 'florist', 'phone' => '+48' }).sort)
    assert_equal([], Watches.match_osm_filters_tags(watches, { 'shop' => 'fish', 'phone' => '+48' }))
    assert_equal([], Watches.match_osm_filters_tags(watches, { 'phone' => '+48' }))
  end

  def test_osm_filters_tags_to_sql
    watches = {
      amenity: Watch.new(
        osm_filters_tags: [{ 'amenity' => nil }],
      ),
      florist: Watch.new(
        osm_filters_tags: [{ 'shop' => 'florist' }]
      ),
      pizza: Watch.new(
        osm_filters_tags: [{ 'shop' => /pizza.*/ }]
      ),
    }

    filters = Watches.all_osm_filters_tags(watches)
    sql = Watches.osm_filters_tags_to_sql(filters)

    assert_equal("(tags?'amenity') OR (tags?'shop' AND tags->>'shop' = 'florist') OR (tags?'shop' AND tags->>'shop' ~ '(?-mix:pizza.*)')", sql)
  end
end
