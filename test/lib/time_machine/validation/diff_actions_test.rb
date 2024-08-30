# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/osm/types'
require './lib/time_machine/validation/types'
require './lib/time_machine/validation/diff_actions'
require './lib/time_machine/validation/changes_db'


class TestValidation < Test::Unit::TestCase
  extend T::Sig

  @@fixture_changeset1 = T.let({
    'id' => 1,
    'created_at' => 'now',
    'closed_at' => 'now',
    'open' => false,
    'user' => 'bob',
    'uid' => 1,
    'min_lat' => 0,
    'min_lon' => 0,
    'max_lat' => 0,
    'max_lon' => 0,
    'comments_count' => 0,
    'changes_count' => 1,
    'tags' => {},
  }, Osm::Changeset)

  @@fixture_node_a = T.let({
    'locha_id' => 1,
    'objtype' => 'n',
    'id' => 1,
    'geom' => nil,
    'geom_distance' => 0,
    'deleted' => false,
    'members' => nil,
    'version' => 1,
    'changesets' => [@@fixture_changeset1],
    'username' => 'bob',
    'created' => 'today',
    'tags' => T.let({
      'foo' => 'bar',
    }, T::Hash[String, String]),
    'is_change' => false,
    'group_ids' => nil,
    }, Validation::OSMChangeProperties)

  @@fixture_node_b = T.let({
    'locha_id' => 1,
    'objtype' => 'n',
    'id' => 1,
    'geom' => 'Point(1 1)',
    'geom_distance' => 1,
    'deleted' => false,
    'members' => nil,
    'version' => 2,
    'changesets' => [@@fixture_changeset1],
    'username' => 'bob',
    'created' => 'today',
    'tags' => {
      'bar' => 'foo',
    },
    'is_change' => true,
    'group_ids' => nil,
    }, Validation::OSMChangeProperties)

  sig { void }
  def test_diff_osm_object_same
    diff = Validation.diff_osm_object(@@fixture_node_a, @@fixture_node_a)
    assert_equal(Validation::DiffActions.new(attribs: {}, tags: {}).inspect, diff.inspect)
  end

  sig { void }
  def test_diff_osm_object_nil_before
    diff = Validation.diff_osm_object(nil, @@fixture_node_a)
    assert_equal(
      Validation::DiffActions.new(
        attribs: { 'deleted' => [], 'geom_distance' => [] },
        tags: { 'foo' => [] },
      ).inspect,
      diff.inspect
    )
  end

  sig { void }
  def test_diff_osm_object_nil_after
    diff = Validation.diff_osm_object(@@fixture_node_a, nil)
    assert_equal(
      Validation::DiffActions.new(
        attribs: { 'deleted' => [], 'geom_distance' => [] },
        tags: { 'foo' => [] },
      ).inspect,
      diff.inspect
    )
  end

  sig { void }
  def test_diff_osm_object
    diff = Validation.diff_osm_object(@@fixture_node_a, @@fixture_node_b)
    assert_equal(
      Validation::DiffActions.new(
        attribs: { 'geom_distance' => [] },
        tags: { 'foo' => [], 'bar' => [] },
      ).inspect,
      diff.inspect
    )
  end
end
