# typed: true
# frozen_string_literal: true
# typed: yes

require 'sorbet-runtime'
require 'test/unit'
require './time_machine/validators/validator'
require './time_machine/validators/tags_changes'
require './time_machine/validators/user_list'
require './time_machine/time_machine'
require './time_machine/types'
require './time_machine/config'


class TestValidator < Test::Unit::TestCase
  extend T::Sig

  def test_simple
    id = 'foo'
    action = 'accept'
    validator = Validators::Validator.new(id: id, action: action)

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
    validator = Validators::Validator.new(id: id, action_force: action)

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
    validator = Validators::UserList.new(id: id, action: action, list: ['bob'])
    validation_action = [Types::Action.new(
      validator_id: id,
      description: nil,
      action: action,
    )]

    after = {
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
    }

    diff = TimeMachine.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'lat' => validation_action, 'lon' => validation_action },
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
    watches = Validators::Watches.new([
      Validators::Watch.new(
        match: '[shop=florist]',
        watch: { 'phone' => nil, 'fee' => nil },
      ),
  ])
    validator = Validators::TagsChanges.new(id: id, watches: watches, accept: 'action_accept', reject: 'action_reject')
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

    after = {
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
        'shop' => 'florist',
        'phone' => '+48',
        'foo' => 'bar',
      },
      'change_distance' => 0,
    }

    diff = TimeMachine.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'lat' => [], 'lon' => [] },
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
    validator = Validators::TagsNonSignificantAdd.new(id: id, config: config, action: 'accept')
    validation_action_accept = [Types::Action.new(
      validator_id: id,
      description: nil,
      action: 'accept',
    )]

    after = {
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
        'shop' => 'florist',
        'phone' => '+48',
        'foo' => 'bar',
      },
      'change_distance' => 0,
    }

    diff = TimeMachine.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      TimeMachine::DiffActions.new(
        attribs: { 'lat' => [], 'lon' => [] },
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
