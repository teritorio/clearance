# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/osm/tags_matches'


class TestTagsMatchs < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_match_value
    assert_equal(['[p]'], Osm::TagsMatch.new(['[p]']).match({ 'p' => '+48' }).collect(&:first))

    assert_equal(['[p="+48"]'], Osm::TagsMatch.new(['[p="+48"]']).match({ 'p' => '+48' }).collect(&:first))
    assert_equal([], Osm::TagsMatch.new(['[p="+48"]']).match({ 'p' => '+4' }).collect(&:first))

    assert_equal(['[p~4]'], Osm::TagsMatch.new(['[p~4]']).match({ 'p' => '+48' }).collect(&:first))
    assert_equal([], Osm::TagsMatch.new(['[p~5]']).match({ 'p' => '+48' }).collect(&:first))

    assert_equal([], Osm::TagsMatch.new(['[highway=footway][footway=traffic_island]']).match({ 'highway' => 'footway' }).collect(&:first))
    assert_equal(['[footway=traffic_island][highway=footway]'], Osm::TagsMatch.new(['[highway=footway][footway=traffic_island]']).match({ 'highway' => 'footway', 'footway' => 'traffic_island' }).collect(&:first))

    assert_equal(['[!footway][highway=footway]'], Osm::TagsMatch.new(['[highway=footway][!footway]']).match({ 'highway' => 'footway' }).collect(&:first))
    assert_equal([], Osm::TagsMatch.new(['[highway=footway][!footway]']).match({ 'highway' => 'footway', 'footway' => 'traffic_island' }).collect(&:first))
  end

  sig { void }
  def test_matches
    amenity = Osm::TagsMatch.new(['[amenity~".*"]'])
    florist = Osm::TagsMatch.new(['[shop=florist]'])
    matches = Osm::TagsMatches.new([amenity, florist])

    assert_equal([['[shop=florist]', florist]], matches.match({ 'shop' => 'florist' }))
    assert_equal([], matches.match({ 'shop' => 'fish' }))
    assert_equal([['[shop=florist]', florist]], matches.match({ 'shop' => 'florist', 'phone' => '+48' }))
    assert_equal([], matches.match({ 'shop' => 'fish', 'phone' => '+48' }))
    assert_equal([], matches.match({ 'phone' => '+48' }))
    assert_equal([['[amenity~".*"]', amenity]], matches.match({ 'amenity' => 'pole' }))
  end

  sig { void }
  def test_match_with_extra
    florist = Osm::TagsMatch.new(['[shop=florist]'], selector_extra: { 'phone' => nil })
    matches = Osm::TagsMatches.new([florist])

    assert_equal([['[shop=florist]', florist], ['phone', florist], ['shop', florist]], matches.match_with_extra({ 'shop' => 'florist', 'phone' => '+2', 'fax' => 'forgot' }))
  end

  sig { void }
  def test_matches_to_sql
    matches = Osm::TagsMatches.new([
      Osm::TagsMatch.new(['[amenity]']),
      Osm::TagsMatch.new(['[shop=florist]']),
      Osm::TagsMatch.new(['[shop~"pizza.*"]']),
      Osm::TagsMatch.new(['[highway=footway][footway=traffic_island]']),
    ])
    sql = matches.to_sql('postgres', nil)
    assert_equal("(tags?'amenity') OR ((tags?'shop' AND tags->>'shop' = 'florist')) OR ((tags?'shop' AND tags->>'shop' ~ 'pizza.*')) OR ((tags?'highway' AND tags->>'highway' = 'footway') AND (tags?'footway' AND tags->>'footway' = 'traffic_island'))", sql)

    matches = Osm::TagsMatches.new([
      Osm::TagsMatch.new(['[amenity]', '[shop]']),
    ])
    sql = matches.to_sql('postgres', nil)
    assert_equal("((tags?'amenity') OR (tags?'shop'))", sql)

    matches = Osm::TagsMatches.new([
      Osm::TagsMatch.new(['[!amenity]']),
    ])
    sql = matches.to_sql('postgres', nil)
    assert_equal("(NOT tags?'amenity')", sql)
  end
end
