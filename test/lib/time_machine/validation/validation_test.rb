# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/osm/types'
require './lib/time_machine/validation/types'
require './lib/time_machine/validation/time_machine'


class TestValidation < Test::Unit::TestCase
  extend T::Sig

  @@fixture_changeset1 = T.let({
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
  }, Osm::Changeset)

  @@fixture_node_a = T.let({
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
  def test_object_validation1
    validation = Validation.object_validation(Configuration::Config.new, [@@fixture_node_a])
    validation_result = Validation::ValidationResult.new(
      action: nil,
      version: @@fixture_node_a['version'],
      deleted: @@fixture_node_a['deleted'],
      changeset_ids: @@fixture_node_a['changesets'].pluck('id'),
      created: @@fixture_node_a['created'],
      diff: Validation::DiffActions.new(
        attribs: { 'geom' => [] },
        tags: { 'foo' => [] },
      ),
    )
    assert_equal(validation_result.inspect, validation.inspect)
  end

  sig { void }
  def test_object_validation_same
    validation = Validation.object_validation(Configuration::Config.new, [@@fixture_node_a, @@fixture_node_a])
    validation_result = Validation::ValidationResult.new(
      action: 'accept',
      version: @@fixture_node_a['version'],
      deleted: @@fixture_node_a['deleted'],
      changeset_ids: @@fixture_node_a['changesets'].pluck('id'),
      created: @@fixture_node_a['created'],
      diff: Validation::DiffActions.new(
        attribs: {},
        tags: {},
      ),
    )
    assert_equal(validation_result.inspect, validation.inspect)
  end

  sig { void }
  def test_object_validation2
    validation = Validation.object_validation(Configuration::Config.new, [@@fixture_node_a, @@fixture_node_b])
    validation_result = Validation::ValidationResult.new(
      action: nil,
      version: @@fixture_node_b['version'],
      deleted: @@fixture_node_b['deleted'],
      changeset_ids: @@fixture_node_a['changesets'].pluck('id'),
      created: @@fixture_node_b['created'],
      diff: Validation::DiffActions.new(
        attribs: { 'geom' => [] },
        tags: { 'foo' => [], 'bar' => [] },
      ),
    )
    assert_equal(validation_result.inspect, validation.inspect)
  end

  sig { void }
  def test_object_validation_many
    id = 'all'
    ['accept', 'reject', nil].each{ |action|
      validation = Validation.object_validation(
        Configuration::Config.new(validators: [Validators::All.new(id: id, osm_tags_matches: Osm::TagsMatches.new([]), action: action)]),
        [@@fixture_node_a, @@fixture_node_b],
      )

      validated = [Validation::Action.new(
        validator_id: id,
        action: action || 'reject',
      )]
      validation_result = Validation::ValidationResult.new(
        action: action || 'reject',
        version: @@fixture_node_b['version'],
        deleted: @@fixture_node_b['deleted'],
        changeset_ids: @@fixture_node_b['changesets'].pluck('id'),
        created: @@fixture_node_b['created'],
        diff: Validation::DiffActions.new(
          attribs: { 'geom' => validated },
          tags: { 'foo' => validated, 'bar' => validated },
        ),
      )
      assert_equal(validation_result.inspect, validation.inspect)
    }
  end
end
