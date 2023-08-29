# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/types'
require './lib/time_machine/time_machine'


class TestTimeMachine < Test::Unit::TestCase
  extend T::Sig

  @@fiture_changeset1 = T.let({
    'id' => 1,
    'created_at' => 'now',
    'closed_at' => 'now',
    'open' => false,
    'user' => 'bob',
    'uid' => 1,
    'minlat' => 0,
    'minlon' => 0,
    'maxlat' => 0,
    'maxlon' => 0,
    'comments_count' => 0,
    'changes_count' => 1,
    'tags' => {},
  }, Changeset::Changeset)

  @@fixture_node_a = T.let({
    'geom' => nil,
    'geom_distance' => 0,
    'deleted' => false,
    'members' => nil,
    'version' => 1,
    'changesets' => [@@fiture_changeset1],
    'username' => 'bob',
    'created' => 'today',
    'tags' => T.let({
      'foo' => 'bar',
    }, T::Hash[String, String]),
    'group_ids' => nil,
    }, ChangesDb::OSMChangeProperties)

  @@fixture_node_b = T.let({
    'geom' => 'Point(1 1)',
    'geom_distance' => 1,
    'deleted' => false,
    'members' => nil,
    'version' => 2,
    'changesets' => [@@fiture_changeset1],
    'username' => 'bob',
    'created' => 'today',
    'tags' => {
      'bar' => 'foo',
    },
    'group_ids' => nil,
    }, ChangesDb::OSMChangeProperties)

  @@fixture_way_a = T.let({
    'geom' => nil,
    'geom_distance' => 0,
    'deleted' => false,
    'members' => nil,
    'version' => 1,
    'changesets' => nil,
    'username' => 'bob',
    'created' => 'today',
    'tags' => {
      'foo' => 'bar',
    },
    'group_ids' => nil,
    }, ChangesDb::OSMChangeProperties)

  sig {
    params(
      title: T::Hash[String, String],
      description: T::Hash[String, String],
      validators: T::Array[Validators::ValidatorBase],
      osm_tags_matches: OsmTagsMatches::OsmTagsMatches,
      main_contacts: T::Array[String],
      user_groups: T::Hash[String, Configuration::UserGroupConfig],
      project_tags: T::Array[String],
    ).returns(Configuration::Config)
  }
  def config(title: {}, description: {}, validators: [], osm_tags_matches: OsmTagsMatches::OsmTagsMatches.new([]), main_contacts: [], user_groups: {}, project_tags: [])
    Configuration::Config.new(
        title: title,
        description: description,
        validators: validators,
        osm_tags_matches: osm_tags_matches,
        main_contacts: main_contacts,
        user_groups: user_groups,
        project_tags: project_tags,
      )
  end

  sig { void }
  def test_diff_osm_object_same
    diff = TimeMachine.diff_osm_object(@@fixture_node_a, @@fixture_node_a)
    assert_equal(TimeMachine::DiffActions.new(attribs: {}, tags: {}).inspect, diff.inspect)
  end

  sig { void }
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

  sig { void }
  def test_object_validation_empty
    validation = TimeMachine.object_validation(config, [@@fixture_node_a])
    validation_result = TimeMachine::ValidationResult.new(
      action: nil,
      version: @@fixture_node_a['version'],
      deleted: @@fixture_node_a['deleted'],
      changeset_ids: @@fixture_node_a['changesets'].pluck('id'),
      created: @@fixture_node_a['created'],
      diff: TimeMachine::DiffActions.new(
        attribs: { 'geom' => [] },
        tags: { 'foo' => [] },
      ),
    )
    assert_equal(validation_result.inspect, validation.inspect)

    validation = TimeMachine.object_validation(config, [@@fixture_node_a, @@fixture_node_a])
    validation_result = TimeMachine::ValidationResult.new(
      action: 'accept',
      version: @@fixture_node_a['version'],
      deleted: @@fixture_node_a['deleted'],
      changeset_ids: @@fixture_node_a['changesets'].pluck('id'),
      created: @@fixture_node_a['created'],
      diff: TimeMachine::DiffActions.new(
        attribs: {},
        tags: {},
      ),
    )
    assert_equal(validation_result.inspect, validation.inspect)
  end

  sig { void }
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
      validation_result = TimeMachine::ValidationResult.new(
        action: action || 'reject',
        version: @@fixture_node_b['version'],
        deleted: @@fixture_node_b['deleted'],
        changeset_ids: @@fixture_node_b['changesets'].pluck('id'),
        created: @@fixture_node_b['created'],
        diff: TimeMachine::DiffActions.new(
          attribs: { 'geom' => validated },
          tags: { 'foo' => validated, 'bar' => validated },
        ),
      )
      assert_equal(validation_result.inspect, validation.inspect)
    }
  end
end
