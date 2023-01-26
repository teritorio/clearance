# frozen_string_literal: true
# typed: yes

require 'sorbet-runtime'
require 'test/unit'
require './time_machine/osm_tags_matches'


class TestOsmTagsMatchs < Test::Unit::TestCase
  extend T::Sig

  def test_match_value
    assert_equal(['p'], OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'p' => nil })]).match({ 'p' => '+48' }))

    assert_equal(['p'], OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'p' => '+48' })]).match({ 'p' => '+48' }))
    assert_equal([], OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'p' => '+48' })]).match({ 'p' => '+4' }))

    assert_equal(['p'], OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'p' => /4/ })]).match({ 'p' => '+48' }))
    assert_equal([], OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'p' => /5/ })]).match({ 'p' => '+48' }))
  end

  def test_matches
    matches = OsmTagsMatches::OsmTagsMatches.new({
      amenity: OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'amenity' => /.*/ })]),
      florist: OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'shop' => 'florist' })]),
    })

    assert_equal(['shop'], matches.match({ 'shop' => 'florist' }))
    assert_equal([], matches.match({ 'shop' => 'fish' }))
    assert_equal(['shop'], matches.match({ 'shop' => 'florist', 'phone' => '+48' }))
    assert_equal([], matches.match({ 'shop' => 'fish', 'phone' => '+48' }))
    assert_equal([], matches.match({ 'phone' => '+48' }))
    assert_equal(['amenity'], matches.match({ 'amenity' => 'pole' }))
  end

  def test_matches_to_sql
    matches = OsmTagsMatches::OsmTagsMatches.new({
      amenity: OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'amenity' => nil })]),
      florist: OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'shop' => 'florist' })]),
      pizza: OsmTagsMatches::OsmTagsMatchSet.new([OsmTagsMatches::OsmTagsMatch.new({ 'shop' => /pizza.*/ })]),
    })

    sql = matches.to_sql
    assert_equal("(tags?'amenity') OR (tags?'shop' AND (tags->>'shop' = 'florist')) OR (tags?'shop' AND (tags->>'shop' ~ '(?-mix:pizza.*)'))", sql)
  end
end