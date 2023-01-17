# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'test/unit'
require './time_machine/osm_tags_filters'


class TestOsmTagsFilters < Test::Unit::TestCase
  extend T::Sig

  # def test_all_osm_filters_tags
  #   osm_tags_filter = OsmTagsFilters::OsmTagsFilters.new({
  #     amenity: OsmTagsFilters::OsmTagsFilter.new([{ 'amenity' => /.*/ }]),
  #     florist: OsmTagsFilters::OsmTagsFilter.new([{ 'shop' => 'florist' }]),
  #   })
  #   filters = osm_tags_filter.all_osm_filters_tags

  #   assert_equal(2, filters.size)
  # end

  def test_match_value
    assert_equal(['p'], OsmTagsFilters::OsmTagsFilter.new([{ 'p' => nil }]).match({ 'p' => '+48' }))

    assert_equal(['p'], OsmTagsFilters::OsmTagsFilter.new([{ 'p' => '+48' }]).match({ 'p' => '+48' }))
    assert_equal([], OsmTagsFilters::OsmTagsFilter.new([{ 'p' => '+48' }]).match({ 'p' => '+4' }))

    assert_equal(['p'], OsmTagsFilters::OsmTagsFilter.new([{ 'p' => /4/ }]).match({ 'p' => '+48' }))
    assert_equal([], OsmTagsFilters::OsmTagsFilter.new([{ 'p' => /5/ }]).match({ 'p' => '+48' }))
  end

  def test_match_osm_filters_tags
    osm_tags_filters = OsmTagsFilters::OsmTagsFilters.new({
      amenity: OsmTagsFilters::OsmTagsFilter.new([{ 'amenity' => /.*/ }]),
      florist: OsmTagsFilters::OsmTagsFilter.new([{ 'shop' => 'florist' }]),
    })

    assert_equal(['shop'], osm_tags_filters.match({ 'shop' => 'florist' }))
    assert_equal([], osm_tags_filters.match({ 'shop' => 'fish' }))
    assert_equal(['shop'], osm_tags_filters.match({ 'shop' => 'florist', 'phone' => '+48' }))
    assert_equal([], osm_tags_filters.match({ 'shop' => 'fish', 'phone' => '+48' }))
    assert_equal([], osm_tags_filters.match({ 'phone' => '+48' }))
    assert_equal(['amenity'], osm_tags_filters.match({ 'amenity' => 'pole' }))
  end

  def test_osm_filters_tags_to_sql
    osm_tags_filters = OsmTagsFilters::OsmTagsFilters.new({
      amenity: OsmTagsFilters::OsmTagsFilter.new([{ 'amenity' => nil }]),
      florist: OsmTagsFilters::OsmTagsFilter.new([{ 'shop' => 'florist' }]),
      pizza: OsmTagsFilters::OsmTagsFilter.new([{ 'shop' => /pizza.*/ }]),
    })

    sql = osm_tags_filters.to_sql
    assert_equal("(tags?'amenity') OR (tags?'shop' AND (tags->>'shop' = 'florist')) OR (tags?'shop' AND (tags->>'shop' ~ '(?-mix:pizza.*)'))", sql)
  end
end
