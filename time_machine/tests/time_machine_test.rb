# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'test/unit'
require './time_machine'


class TestTimeMachine < Test::Unit::TestCase
  extend T::Sig

  @@fixture_node_a = T.let({
    'lat' => 0.0,
    'lon' => 0.0,
    'nodes' => nil,
    'deleted' => false,
    'members' => nil,
    'version' => 1,
    'changeset_id' => 1,
    'uid' => 1,
    'username' => 'bob',
    'created' => 'today',
    'tags' => {
      'foo' => 'bar',
    },
  }, ChangesDB::OSMChangeProperties)

  @@fixture_way_a = T.let({
    'lat' => nil,
    'lon' => nil,
    'nodes' => [1, 2],
    'deleted' => false,
    'members' => nil,
    'version' => 1,
    'changeset_id' => 1,
    'uid' => 1,
    'username' => 'bob',
    'created' => 'today',
    'tags' => {
      'foo' => 'bar',
    },
  }, ChangesDB::OSMChangeProperties)

  def test_diff_osm_object_same
    diff = TimeMachine.diff_osm_object(@@fixture_node_a, @@fixture_node_a)
    assert_equal(TimeMachine::DiffActions.new(attribs: {}, tags: {}).inspect, diff.inspect)
  end

  def test_diff_osm_object_nil
    diff = TimeMachine.diff_osm_object(nil, @@fixture_node_a)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'lat' => [], 'lon' => [] },
        tags: { 'foo' => [] },
      ).inspect,
      diff.inspect
    )

    diff = TimeMachine.diff_osm_object(nil, @@fixture_way_a)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'nodes' => [] },
        tags: { 'foo' => [] },
      ).inspect,
      diff.inspect
    )
  end

  def test_object_validation_empty
    validation = TimeMachine.object_validation([], [@@fixture_node_a])
    validation_result = [TimeMachine::ValidationResult.new(
      action: nil,
      version: @@fixture_node_a['version'],
      created: @@fixture_node_a['created'],
      uid: @@fixture_node_a['uid'],
      username: @@fixture_node_a['username'],
      diff: TimeMachine::DiffActions.new(
        attribs: { 'lat' => [], 'lon' => [] },
        tags: { 'foo' => [] },
      ),
    )]
    assert_equal(validation_result.inspect, validation.inspect)

    validation = TimeMachine.object_validation([], [@@fixture_node_a, @@fixture_node_a])
    validation_result = [TimeMachine::ValidationResult.new(
      action: 'accept',
      version: @@fixture_node_a['version'],
      created: @@fixture_node_a['created'],
      uid: @@fixture_node_a['uid'],
      username: @@fixture_node_a['username'],
      diff: TimeMachine::DiffActions.new(
        attribs: {},
        tags: {},
      ),
    )]
    assert_equal(validation_result.inspect, validation.inspect)
  end
end
