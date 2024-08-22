# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/logical_history/refs'

Refs = LogicalHistory::Refs

class TestRef < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_refs
    assert_equal(Refs.refs({}), {})
    assert_equal(Refs.refs({ 'foo' => 'b' }), {})
    assert_equal(Refs.refs({ 'ref:a' => 'a' }), { 'ref:a' => 'a' })

    assert_not_equal(Refs.refs({ 'ref:a' => 'a' }), { 'ref:a' => 'b' })
  end
end
