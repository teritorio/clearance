# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/validators/validator'
require './lib/time_machine/validators/tags_changes'
require './lib/time_machine/validators/user_list'
require './lib/time_machine/validation/time_machine'
require './lib/time_machine/validation/types'
require './lib/time_machine/configuration'


class TestValidator < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_simple
    id = 'foo'
    action = 'accept'
    validator = Validators::Validator.new(id: id, osm_tags_matches: Osm::TagsMatches.new([]), action: action)

    actions = T.let([], T::Array[Validation::Action])
    validator.assign_action(actions)

    assert_equal(1, actions.size)
    a = T.must(actions[0])
    assert_equal(id, a.validator_id)
    assert_equal(action, a.action)
  end

  sig { void }
  def test_action_force
    id = 'foo'
    action = 'accept'
    validator = Validators::Validator.new(id: id, osm_tags_matches: Osm::TagsMatches.new([]), action_force: action)

    actions = T.let([], T::Array[Validation::Action])
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

  sig { void }
  def test_simple
    id = 'foo'
    action = 'accept'
    osm_tags_matches = Osm::TagsMatches.new([
      Osm::TagsMatch.new(['[foo=bar]']),
    ])
    validator = Validators::UserList.new(id: id, osm_tags_matches: osm_tags_matches, action: action, list: ['bob'])
    validation_action = [Validation::Action.new(
      validator_id: id,
      description: nil,
      action: action,
    )]

    after = Validation::OSMChangeProperties.new(
      locha_id: 1,
      objtype: 'n',
      id: 1,
      geom: 'Point(0 0)',
      geom_distance: 0,
      deleted: false,
      members: nil,
      version: 1,
      changesets: nil,
      username: 'bob',
      created: 'today',
      tags: {
        'foo' => 'barbar',
      },
      is_change: true,
      group_ids: nil,
    )

    diff = Validation.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      Validation::DiffActions.new(
        attribs: { 'deleted' => validation_action, 'geom_distance' => validation_action },
        tags: { 'foo' => validation_action }
      ).inspect,
      diff.inspect
    )

    diff = Validation.diff_osm_object(after, after)
    validator.apply(after, after, diff)
    assert_equal(
      Validation::DiffActions.new(
        attribs: {},
        tags: {}
      ).inspect,
      diff.inspect
    )
  end
end

class TestTagsChanges < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_simple
    id = 'foo'
    osm_tags_matches = Osm::TagsMatches.new([
      Osm::TagsMatch.new(
        ['[shop=florist]'],
        selector_extra: { 'phone' => nil, 'fee' => nil },
      ),
    ])
    validator = Validators::TagsChanges.new(id: id, osm_tags_matches: osm_tags_matches, accept: 'action_accept', reject: 'action_reject')
    validation_action_accept = [Validation::Action.new(
      validator_id: 'action_accept',
      description: nil,
      action: 'accept',
    )]
    validation_action_reject = [Validation::Action.new(
      validator_id: 'action_reject',
      description: nil,
      action: 'reject',
    )]

    after = Validation::OSMChangeProperties.new(
      locha_id: 1,
      objtype: 'n',
      id: 1,
      geom: 'Point(0 0)',
      geom_distance: 0,
      deleted: false,
      members: nil,
      version: 1,
      changesets: nil,
      username: 'bob',
      created: 'today',
      tags: {
        'shop' => 'florist',
        'phone' => '+48',
        'foo' => 'bar',
      },
      is_change: true,
      group_ids: nil,
    )

    diff = Validation.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      Validation::DiffActions.new(
        attribs: { 'deleted' => [], 'geom_distance' => [] },
        tags: { 'shop' => validation_action_reject, 'phone' => validation_action_reject, 'foo' => validation_action_accept }
      ).inspect,
      diff.inspect
    )

    # No change
    diff = Validation.diff_osm_object(after, after)
    validator.apply(after, after, diff)
    assert_equal(
      Validation::DiffActions.new(
        attribs: {},
        tags: {}
      ).inspect,
      diff.inspect
    )
  end
end

class TestGeomNewObject < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_simple
    id = 'foo'
    osm_tags_matches = Osm::TagsMatches.new([
      Osm::TagsMatch.new(
        ['[shop=florist]'],
        selector_extra: { 'phone' => nil, 'fee' => nil },
      ),
    ])
    validator = Validators::GeomNewObject.new(id: id, osm_tags_matches: osm_tags_matches, action: 'accept')
    validation_action_accept = [Validation::Action.new(
      validator_id: id,
      description: nil,
      action: 'accept',
    )]

    after = Validation::OSMChangeProperties.new(
      locha_id: 1,
      objtype: 'n',
      id: 1,
      geom: 'Point(0 0)',
      geom_distance: 0,
      deleted: false,
      members: nil,
      version: 1,
      changesets: nil,
      username: 'bob',
      created: 'today',
      tags: {
        'shop' => 'florist',
      },
      is_change: false,
      group_ids: nil,
    )

    diff = Validation.diff_osm_object(nil, after)
    validator.apply(nil, after, diff)
    assert_equal(
      Validation::DiffActions.new(
        attribs: { 'deleted' => [], 'geom_distance' => validation_action_accept },
        tags: { 'shop' => [] }
      ).inspect,
      diff.inspect
    )
  end
end

class TestGeomChanges < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_no_dist
    id = 'foo'
    osm_tags_matches = Osm::TagsMatches.new([
      Osm::TagsMatch.new(
        ['[shop=florist]'],
        selector_extra: { 'phone' => nil, 'fee' => nil },
      ),
    ])
    validator = Validators::GeomChanges.new(id: id, osm_tags_matches: osm_tags_matches, dist: nil, action: 'accept')
    validation_action_accept = [Validation::Action.new(
      validator_id: id,
      description: nil,
      action: 'accept',
    )]

    before = Validation::OSMChangeProperties.new(
      locha_id: 1,
      objtype: 'n',
      id: 1,
      geom: 'Point(10 10)',
      geom_distance: 0,
      deleted: false,
      members: nil,
      version: 1,
      changesets: nil,
      username: 'bob',
      created: 'today',
      tags: {
        'shop' => 'florist',
      },
      is_change: false,
      group_ids: nil,
    )

    after = Validation::OSMChangeProperties.new(
      locha_id: 1,
      objtype: 'n',
      id: 1,
      geom: 'Point(0 0)',
      geom_distance: 0,
      deleted: false,
      members: nil,
      version: 1,
      changesets: nil,
      username: 'bob',
      created: 'today',
      tags: {
        'shop' => 'florist',
      },
      is_change: true,
      group_ids: nil,
    )

    diff = Validation.diff_osm_object(before, after)
    diff.attribs['geom_distance'] = []
    puts diff.inspect
    validator.apply(before, after, diff)
    assert_equal(
      Validation::DiffActions.new(
        attribs: { 'geom_distance' => validation_action_accept },
        tags: {}
      ).inspect,
      diff.inspect
    )
  end

  sig { void }
  def test_dist
    id = 'foo'
    osm_tags_matches = Osm::TagsMatches.new([
      Osm::TagsMatch.new(
        ['[shop=florist]'],
        selector_extra: { 'phone' => nil, 'fee' => nil },
      ),
    ])
    validator = Validators::GeomChanges.new(id: id, osm_tags_matches: osm_tags_matches, dist: 1, action: 'accept')
    validation_action_accept = [Validation::Action.new(
      validator_id: id,
      description: nil,
      action: 'accept',
      options: { 'dist' => 10 },
    )]

    before = Validation::OSMChangeProperties.new(
      locha_id: 1,
      objtype: 'n',
      id: 1,
      geom: 'Point(10 10)',
      geom_distance: 0,
      deleted: false,
      members: nil,
      version: 1,
      changesets: nil,
      username: 'bob',
      created: 'today',
      tags: {
        'shop' => 'florist',
      },
      is_change: false,
      group_ids: nil,
    )

    after = Validation::OSMChangeProperties.new(
      locha_id: 1,
      objtype: 'n',
      id: 1,
      geom: 'Point(0 0)',
      geom_distance: 10,
      deleted: false,
      members: nil,
      version: 1,
      changesets: nil,
      username: 'bob',
      created: 'today',
      tags: {
        'shop' => 'florist',
      },
      is_change: true,
      group_ids: nil,
    )

    diff = Validation.diff_osm_object(before, after)
    diff.attribs['geom_distance'] = []
    puts diff.inspect
    validator.apply(before, after, diff)
    assert_equal(
      Validation::DiffActions.new(
        attribs: { 'geom_distance' => validation_action_accept },
        tags: {}
      ).inspect,
      diff.inspect
    )
  end
end
