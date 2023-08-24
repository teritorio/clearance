# typed: true
# frozen_string_literal: true
# typed: yes

require 'sorbet-runtime'
require 'test/unit'
require './time_machine/types'
require './time_machine/time_machine'


class TestTimeMachine < Test::Unit::TestCase
  extend T::Sig

  @@fixture_node_a = T.let({
    'geom' => nil,
    'geom_distance' => 0,
    'deleted' => false,
    'members' => nil,
    'version' => 1,
    'changeset' => nil,
    'changeset_id' => 1,
    'username' => 'bob',
    'created' => 'today',
    'tags' => T.let({
      'foo' => 'bar',
    }, T::Hash[String, String]),
  }, ChangesDb::OSMChangeProperties)

  @@fixture_node_b = T.let({
    'geom' => 'Point(1 1)',
    'geom_distance' => 1,
    'deleted' => false,
    'members' => nil,
    'version' => 2,
    'changeset' => nil,
    'changeset_id' => 2,
    'username' => 'bob',
    'created' => 'today',
    'tags' => {
      'bar' => 'foo',
    },
  }, ChangesDb::OSMChangeProperties)

  @@fixture_way_a = T.let({
    'geom' => nil,
    'geom_distance' => 0,
    'deleted' => false,
    'members' => nil,
    'version' => 1,
    'changeset' => nil,
    'changeset_id' => 1,
    'username' => 'bob',
    'created' => 'today',
    'tags' => {
      'foo' => 'bar',
    },
  }, ChangesDb::OSMChangeProperties)

  def config(validators: [], title: {}, description: {}, osm_tags_matches: OsmTagsMatches::OsmTagsMatches.new([]), user_groups: {})
    Configuration::Config.new(
        title: title,
        description: description,
        validators: validators,
        osm_tags_matches: osm_tags_matches,
        user_groups: user_groups,
      )
  end

  def test_diff_osm_object_same
    diff = TimeMachine.diff_osm_object(@@fixture_node_a, @@fixture_node_a)
    assert_equal(TimeMachine::DiffActions.new(attribs: {}, tags: {}).inspect, diff.inspect)
  end

  def test_diff_osm_object_nil
    diff = TimeMachine.diff_osm_object(nil, @@fixture_node_a)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'geom_distance' => [] },
        tags: { 'foo' => [] },
      ).inspect,
      diff.inspect
    )

    diff = TimeMachine.diff_osm_object(nil, @@fixture_way_a)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'geom_distance' => [] },
        tags: { 'foo' => [] },
      ).inspect,
      diff.inspect
    )
  end

  def test_object_validation_empty
    validation = TimeMachine.object_validation(config, [@@fixture_node_a])
    validation_result = [TimeMachine::ValidationResult.new(
      action: nil,
      version: @@fixture_node_a['version'],
      deleted: @@fixture_node_a['deleted'],
      changeset_ids: [@@fixture_node_a['changeset_id']],
      created: @@fixture_node_a['created'],
      diff: TimeMachine::DiffActions.new(
        attribs: { 'geom' => [] },
        tags: { 'foo' => [] },
      ),
    )]
    assert_equal(validation_result.inspect, validation.inspect)

    validation = TimeMachine.object_validation(config, [@@fixture_node_a, @@fixture_node_a])
    validation_result = [TimeMachine::ValidationResult.new(
      action: 'accept',
      version: @@fixture_node_a['version'],
      deleted: @@fixture_node_a['deleted'],
      changeset_ids: [@@fixture_node_a['changeset_id']],
      created: @@fixture_node_a['created'],
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
      validation = TimeMachine.object_validation(
        config(validators: [Validators::All.new(id: id, osm_tags_matches: OsmTagsMatches::OsmTagsMatches.new([]), action: action)]),
        [@@fixture_node_a, @@fixture_node_b],
      )

      validated = [Types::Action.new(
        validator_id: id,
        action: action || 'reject',
      )]
      validation_result = [TimeMachine::ValidationResult.new(
        action: action || 'reject',
        version: @@fixture_node_b['version'],
        deleted: @@fixture_node_b['deleted'],
        changeset_ids: [@@fixture_node_b['changeset_id']],
        created: @@fixture_node_b['created'],
        diff: TimeMachine::DiffActions.new(
          attribs: { 'geom' => validated },
          tags: { 'foo' => validated, 'bar' => validated },
        ),
      )]
      assert_equal(validation_result.inspect, validation.inspect)
    }
  end
end
