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
  def test_matches_to_sql
    matches = OsmTagsMatches::OsmTagsMatches.new([
      OsmTagsMatches::OsmTagsMatch.new('[amenity]'),
      OsmTagsMatches::OsmTagsMatch.new('[shop=florist]'),
      OsmTagsMatches::OsmTagsMatch.new('[shop~pizza.*]'),
    ])

    sql = matches.to_sql(->(s) { "'#{s}'" })
    assert_equal("(tags?'amenity') OR ((tags?'shop' AND tags->>'shop' = 'florist')) OR ((tags?'shop' AND tags->>'shop' ~ '(?-mix:pizza.*)'))", sql)
  end
end
