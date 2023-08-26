# typed: true
# frozen_string_literal: true
# typed: yes

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/validators/validator'
require './lib/time_machine/validators/tags_changes'
require './lib/time_machine/validators/user_list'
require './lib/time_machine/time_machine'
require './lib/time_machine/types'
require './lib/time_machine/configuration'


class TestValidator < Test::Unit::TestCase
  extend T::Sig

  def test_simple
    id = 'foo'
    action = 'accept'
    validator = Validators::Validator.new(id: id, osm_tags_matches: OsmTagsMatches::OsmTagsMatches.new([]), action: action)

    actions = T.let([], T::Array[Types::Action])
    validator.assign_action(actions)

    assert_equal(1, actions.size)
    a = T.must(actions[0])
    assert_equal(id, a.validator_id)
    assert_equal(action, a.action)
  end

  def test_action_force
    id = 'foo'
    action = 'accept'
    validator = Validators::Validator.new(id: id, osm_tags_matches: OsmTagsMatches::OsmTagsMatches.new([]), action_force: action)

    actions = T.let([], T::Array[Types::Action])
    validator.assign_action(actions)
    validator.assign_action(actions)

    assert_equal(1, actions.size)
    a = T.must(actions[0])
    assert_equal(id, a.validator_id)
    assert_equal(action, a.action)
  end
end

class TestUserList < Test::Unit::TestCase
  extend T::Sig

  def test_simple
    id = 'foo'
    action = 'accept'
    osm_tags_matches = OsmTagsMatches::OsmTagsMatches.new([
      OsmTagsMatches::OsmTagsMatch.new('[foo=bar]'),
    ])
    validator = Validators::UserList.new(id: id, osm_tags_matches: osm_tags_matches, action: action, list: ['bob'])
    validation_action = [Types::Action.new(
      validator_id: id,
      description: nil,
      action: action,
    )]

    after = T.let({
      'geom' => 'Point(0 0)',
      'geom_distance' => 0,
      'deleted' => false,
      'members' => nil,
      'version' => 1,
      'changeset_id' => 1,
      'changeset' => nil,
      'username' => 'bob',
      'created' => 'today',
      'tags' => {
        'foo' => 'barbar',
      },
      'group_ids' => [],
    }, ChangesDb::OSMChangeProperties)

    diff = TimeMachine.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'geom_distance' => validation_action },
        tags: { 'foo' => validation_action }
      ).inspect,
      diff.inspect
    )

    diff = TimeMachine.diff_osm_object(after, after)
    validator.apply(after, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: {},
        tags: {}
      ).inspect,
      diff.inspect
    )
  end
end

class TestTagsChanges < Test::Unit::TestCase
  extend T::Sig

  def test_simple
    id = 'foo'
    osm_tags_matches = OsmTagsMatches::OsmTagsMatches.new([
      OsmTagsMatches::OsmTagsMatch.new(
        '[shop=florist]',
        selector_extra: { 'phone' => nil, 'fee' => nil },
      ),
    ])
    validator = Validators::TagsChanges.new(id: id, osm_tags_matches: osm_tags_matches, accept: 'action_accept', reject: 'action_reject')
    validation_action_accept = [Types::Action.new(
      validator_id: 'action_accept',
      description: nil,
      action: 'accept',
    )]
    validation_action_reject = [Types::Action.new(
      validator_id: 'action_reject',
      description: nil,
      action: 'reject',
    )]

    after = T.let({
      'geom' => 'Point(0 0)',
      'geom_distance' => 0,
      'deleted' => false,
      'members' => nil,
      'version' => 1,
      'changeset_id' => 1,
      'changeset' => nil,
      'username' => 'bob',
      'created' => 'today',
      'tags' => {
        'shop' => 'florist',
        'phone' => '+48',
        'foo' => 'bar',
      },
      'group_ids' => [],
    }, ChangesDb::OSMChangeProperties)

    diff = TimeMachine.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'geom_distance' => [] },
        tags: { 'shop' => validation_action_reject, 'phone' => validation_action_reject, 'foo' => validation_action_accept }
      ).inspect,
      diff.inspect
    )

    # No change
    diff = TimeMachine.diff_osm_object(after, after)
    validator.apply(after, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: {},
        tags: {}
      ).inspect,
      diff.inspect
    )
  end
end

class TestTagsNonSignificantAdd < Test::Unit::TestCase
  extend T::Sig

  def test_simple
    id = 'foo'
    config = [
      Validators::TagsNonSignificantChangeConfig.new(
        match: '[shop=florist]',
        values: OsmTagsMatches::OsmTagsMatch.new('[phone]'),
      ),
    ]
    validator = Validators::TagsNonSignificantAdd.new(id: id, osm_tags_matches: OsmTagsMatches::OsmTagsMatches.new([]), config: config, action: 'accept')
    validation_action_accept = [Types::Action.new(
      validator_id: id,
      description: nil,
      action: 'accept',
    )]

    after = T.let({
      'geom' => 'Point(0 0)',
      'geom_distance' => 0,
      'deleted' => false,
      'members' => nil,
      'version' => 1,
      'changeset_id' => 1,
      'changeset' => nil,
      'username' => 'bob',
      'created' => 'today',
      'tags' => {
        'shop' => 'florist',
        'phone' => '+48',
        'foo' => 'bar',
      },
      'group_ids' => [],
    }, ChangesDb::OSMChangeProperties)

    diff = TimeMachine.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'geom_distance' => [] },
        tags: { 'shop' => [], 'phone' => validation_action_accept, 'foo' => [] }
      ).inspect,
      diff.inspect
    )

    # No change
    diff = TimeMachine.diff_osm_object(after, after)
    validator.apply(after, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: {},
        tags: {}
      ).inspect,
      diff.inspect
    )
  end
end
