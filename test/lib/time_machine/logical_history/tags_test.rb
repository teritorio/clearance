# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/logical_history/tags'

Tags = LogicalHistory::Tags

class TestTags < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_key_val_main_distance
    assert_equal(nil, Tags.key_val_main_distance({}, {}))
    assert_equal(0.0, Tags.key_val_main_distance({ 'foo' => 'bar' }, { 'foo' => 'bar' }))
    assert_equal(0.0, Tags.key_val_main_distance({ 'highway' => 'bar' }, { 'highway' => 'bar' }))
    assert_equal(1.0, Tags.key_val_main_distance({ 'highway' => 'bar' }, {}))
    assert_equal(1.0, Tags.key_val_main_distance({}, { 'highway' => 'bar' }))

    assert_equal(1.0, Tags.key_val_main_distance({ 'highway' => 'a' }, { 'highway' => 'b' }))
    assert_equal(1.0, Tags.key_val_main_distance({ 'highway' => 'a' }, { 'highway' => 'ab' }))
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
    assert_equal(0.0, Tags.tags_distance({ 'highway' => 'a' }, { 'highway' => 'a' }))
    assert_equal(0.0, Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'highway' => 'a', 'foo' => 'a' }))
    assert_equal(0.0, Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'highway' => 'a', 'foo' => 'a' }))
    assert_equal(nil, Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'leisure' => 'a', 'foo' => 'a' }))
    assert_equal(nil, Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'foo' => 'a' }))
    assert_equal(0.25, Tags.tags_distance({ 'highway' => 'a', 'foo' => 'a', 'bar' => 'b' }, { 'highway' => 'a', 'foo' => 'a' }))
  end
end
