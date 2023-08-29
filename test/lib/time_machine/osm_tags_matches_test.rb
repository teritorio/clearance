# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/osm_tags_matches'


class TestOsmTagsMatchs < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_match_value
    assert_equal(['p'], OsmTagsMatches::OsmTagsMatch.new('[p]').match({ 'p' => '+48' }).collect(&:first))

    assert_equal(['p'], OsmTagsMatches::OsmTagsMatch.new('[p=+48]').match({ 'p' => '+48' }).collect(&:first))
    assert_equal([], OsmTagsMatches::OsmTagsMatch.new('[p=+48]').match({ 'p' => '+4' }).collect(&:first))

    assert_equal(['p'], OsmTagsMatches::OsmTagsMatch.new('[p~4]').match({ 'p' => '+48' }).collect(&:first))
    assert_equal([], OsmTagsMatches::OsmTagsMatch.new('[p~5]').match({ 'p' => '+48' }).collect(&:first))

    assert_equal([], OsmTagsMatches::OsmTagsMatch.new('[highway=footway][footway=traffic_island]').match({ 'highway' => 'footway' }).collect(&:first))
    assert_equal(%w[highway footway], OsmTagsMatches::OsmTagsMatch.new('[highway=footway][footway=traffic_island]').match({ 'highway' => 'footway', 'footway' => 'traffic_island' }).collect(&:first))
  end

  sig { void }
  def test_matches
    amenity = OsmTagsMatches::OsmTagsMatch.new('[amenity~.*]')
    florist = OsmTagsMatches::OsmTagsMatch.new('[shop=florist]')
    matches = OsmTagsMatches::OsmTagsMatches.new([amenity, florist])

    assert_equal([['shop', florist]], matches.match({ 'shop' => 'florist' }))
    assert_equal([], matches.match({ 'shop' => 'fish' }))
    assert_equal([['shop', florist]], matches.match({ 'shop' => 'florist', 'phone' => '+48' }))
    assert_equal([], matches.match({ 'shop' => 'fish', 'phone' => '+48' }))
    assert_equal([], matches.match({ 'phone' => '+48' }))
    assert_equal([['amenity', amenity]], matches.match({ 'amenity' => 'pole' }))
  end

  sig { void }
  def test_match_with_extra
    florist = OsmTagsMatches::OsmTagsMatch.new('[shop=florist]', selector_extra: { 'phone' => nil })
    matches = OsmTagsMatches::OsmTagsMatches.new([florist])

    assert_equal([['shop', florist], ['phone', florist]], matches.match_with_extra({ 'shop' => 'florist', 'phone' => '+2', 'fax' => 'forgot' }))
  end

  sig { void }
  def test_matches_to_sql
    matches = OsmTagsMatches::OsmTagsMatches.new([
      OsmTagsMatches::OsmTagsMatch.new('[amenity]'),
      OsmTagsMatches::OsmTagsMatch.new('[shop=florist]'),
      OsmTagsMatches::OsmTagsMatch.new('[shop~pizza.*]'),
      OsmTagsMatches::OsmTagsMatch.new('[highway=footway][footway=traffic_island]'),
    ])

    sql = matches.to_sql(->(s) { "'#{s}'" })
    assert_equal("(tags?'amenity') OR ((tags?'shop' AND tags->>'shop' = 'florist')) OR ((tags?'shop' AND tags->>'shop' ~ '(?-mix:pizza.*)')) OR ((tags?'highway' AND tags->>'highway' = 'footway') AND (tags?'footway' AND tags->>'footway' = 'traffic_island'))", sql)
  end
end
