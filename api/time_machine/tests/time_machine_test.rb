# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'test/unit'
require './time_machine/types'
require './time_machine/time_machine'


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
    'change_distance' => 0,
  }, ChangesDb::OSMChangeProperties)

  @@fixture_node_b = T.let({
    'lat' => 1.0,
    'lon' => 1.0,
    'nodes' => nil,
    'deleted' => false,
    'members' => nil,
    'version' => 2,
    'changeset_id' => 2,
    'uid' => 2,
    'username' => 'mom',
    'created' => 'today',
    'tags' => {
      'bar' => 'foo',
    },
    'change_distance' => 0,
  }, ChangesDb::OSMChangeProperties)

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
    'change_distance' => 0,
  }, ChangesDb::OSMChangeProperties)

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
      changeset_id: @@fixture_node_a['changeset_id'],
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
      changeset_id: @@fixture_node_a['changeset_id'],
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

  def test_object_validation_many
    id = 'all'
    ['accept', 'reject', nil].each{ |action|
      accept_validator = Validators::All.new(id:, watches: {}, action:)
      validation = TimeMachine.object_validation(
        [accept_validator],
        [@@fixture_node_a, @@fixture_node_b],
      )

      validated = [Types::Action.new(
        validator_id: id,
        action: action || 'reject',
      )]
      validation_result = [TimeMachine::ValidationResult.new(
        action: action || 'reject',
        version: @@fixture_node_b['version'],
        changeset_id: @@fixture_node_b['changeset_id'],
        created: @@fixture_node_b['created'],
        uid: @@fixture_node_b['uid'],
        username: @@fixture_node_b['username'],
        diff: TimeMachine::DiffActions.new(
          attribs: { 'lat' => validated, 'lon' => validated },
          tags: { 'foo' => validated, 'bar' => validated },
        ),
      )]
      assert_equal(validation_result.inspect, validation.inspect)
    }
  end
end
