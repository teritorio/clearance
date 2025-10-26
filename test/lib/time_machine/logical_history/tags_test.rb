# frozen_string_literal: true
# typed: false

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/logical_history/tags'

Tags = LogicalHistory::Tags

class TestTags < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_key_val_main_distance
    assert_equal(nil, Tags.key_val_main_distance({}, {}))
    assert_equal([0.0, ['foo=bar']], Tags.key_val_main_distance({ 'foo' => 'bar' }, { 'foo' => 'bar' }))
    assert_equal([0.0, ['highway=bar']], Tags.key_val_main_distance({ 'highway' => 'bar' }, { 'highway' => 'bar' }))
    assert_equal([1.0, []], Tags.key_val_main_distance({ 'highway' => 'bar' }, {}))
    assert_equal([1.0, []], Tags.key_val_main_distance({}, { 'highway' => 'bar' }))

    assert_equal([1.0, []], Tags.key_val_main_distance({ 'highway' => 'a' }, { 'highway' => 'b' }))
    assert_equal([0.5, ['highway=primary/secondary']], Tags.key_val_main_distance({ 'highway' => 'primary' }, { 'highway' => 'secondary' }))
  end

  sig { void }
  def test_key_val_fuzzy_distance
    assert_equal(0.5, Tags.key_val_fuzzy_distance({ 'foo' => 'a' }, { 'foo' => 'b' }))
    assert_equal(0.25, Tags.key_val_fuzzy_distance({ 'foo' => 'a' }, { 'foo' => 'ab' }))
    assert_equal(0.25, Tags.key_val_fuzzy_distance({ 'foo' => 'ab' }, { 'foo' => 'ac' }))
    assert_equal(1.0 / 3, Tags.key_val_fuzzy_distance({ 'foo' => 'a' }, { 'foo' => 'abc' }))

    assert_equal(0.5, Tags.key_val_fuzzy_distance({ 'foo' => 'a' }, { 'foo' => 'a', 'bar' => 'b' }))
  end

  sig { void }
  def test_tags_distance
    assert_equal(nil, Tags.tags_distance({ 'a' => 'a' }, { 'a' => 'a' }))
    assert_equal([0.0, nil, nil, 'matched tags: highway=a'], Tags.tags_distance({ 'highway' => 'a' }, { 'highway' => 'a' }))
    assert_equal([0.25, nil, nil, 'matched tags: highway=motorway/trunk'], Tags.tags_distance({ 'highway' => 'motorway' }, { 'highway' => 'trunk' }))
    assert_equal([0.0, nil, nil, 'matched tags: highway=a'], Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'highway' => 'a', 'foo' => 'a' }))
    assert_equal([0.0, nil, nil, 'matched tags: highway=a'], Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'highway' => 'a', 'foo' => 'a' }))
    assert_equal([0.25, { 'landuse' => 'residencial' }, nil, 'matched tags: building=house'], Tags.tags_distance({ 'building' => 'house', 'landuse' => 'residencial' }, { 'building' => 'house' }))
    assert_equal([0.25, nil, { 'landuse' => 'residencial' }, 'matched tags: building=house'], Tags.tags_distance({ 'building' => 'house' }, { 'building' => 'house', 'landuse' => 'residencial' }))
    assert_equal(nil, Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'leisure' => 'a', 'foo' => 'a' }))
    assert_equal(nil, Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'foo' => 'a' }))
    assert_equal([0.25, nil, nil, 'matched tags: highway=a'], Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a', 'bar' => 'b' }, { 'highway' => 'a', 'foo' => 'a' }))
    assert_equal([0.25, { 'building' => 'b' }, nil, 'matched tags: highway=a'], Tags.tags_distance({ 'highway' => 'a', 'building' => 'b' }, { 'highway' => 'a' }))
    assert_equal([0.25, nil, { 'building' => 'b' }, 'matched tags: highway=a'], Tags.tags_distance({ 'highway' => 'a' }, { 'highway' => 'a', 'building' => 'b' }))
    assert_equal([0.375, { 'building' => 'b' }, nil, 'matched tags: highway=motorway/trunk'], Tags.tags_distance({ 'highway' => 'motorway', 'building' => 'b' }, { 'highway' => 'trunk' }))
    assert_equal(nil, Tags.tags_distance({ 'highway' => 'motorway', 'leisure' => 'b' }, { 'leisure' => 'c' }))
    assert_equal([0.75, { 'leisure' => 'b', 'foo' => 'a' }, { 'leisure' => 'c', 'bar' => 'd' }, 'matched tags: highway=a'], Tags.tags_distance({ 'highway' => 'a', 'leisure' => 'b', 'foo' => 'a' }, { 'highway' => 'a', 'leisure' => 'c', 'bar' => 'd' }))
  end
end
