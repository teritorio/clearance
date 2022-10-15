# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'test/unit'
require './validators'
require './time_machine'


class TestValidator < Test::Unit::TestCase
  extend T::Sig
  include Validators

  def test_simple
    id = 'foo'
    action = 'accept'
    validator = Validator.new(id:, action:)

    actions = T.let([], T::Array[Action])
    validator.assign_action(actions)

    assert_equal(1, actions.size)
    a = T.must(actions[0])
    assert_equal(id, a.validator_id)
    assert_equal(action, a.action)
  end

  def test_action_force
    id = 'foo'
    action = 'accept'
    validator = Validator.new(id:, action_force: action)
    puts validator.inspect

    actions = T.let([], T::Array[Action])
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
  include TimeMachine
  include Validators

  def test_simple
    id = 'foo'
    action = 'accept'
    validator = UserList.new(id:, action:, list: ['bob'])
    validator.instance_eval {
      def action
        @action
      end
    }
    validation_action = [validator.action]

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
    }

    diff_attrib, diff_tags = TimeMachine.diff_osm_object(nil, after)
    validator.apply(nil, after, diff_attrib, diff_tags)
    assert_equal(
      { 'lat' => validation_action, 'lon' => validation_action },
      diff_attrib,
    )
    assert_equal(
      { 'foo' => validation_action },
      diff_tags
    )

    diff_attrib, diff_tags = TimeMachine.diff_osm_object(after, after)
    validator.apply(after, after, diff_attrib, diff_tags)
    assert_equal({}, diff_attrib)
    assert_equal({}, diff_tags)
  end
end
