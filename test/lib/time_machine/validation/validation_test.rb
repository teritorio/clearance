# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/osm/types'
require './lib/time_machine/validation/types'
require './lib/time_machine/validation/time_machine'


class TestValidation < Test::Unit::TestCase
  extend T::Sig

  @@srid = T.let(4326, Integer) # No projection
  @@geos_factory = T.let(OSMLogicalHistory.build_geos_factory(@@srid), T.proc.params(geojson_geometry: String).returns(T.nilable(RGeo::Feature::Geometry)))

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
    'created_count' => 1,
    'modified_count' => 1,
    'deleted_count' => 1,
    'tags' => {},
  }, Osm::Changeset)

  @@fixture_node_a = Validation::OSMChangeProperties.new(
    objtype: 'n',
    id: 1,
    geojson_geometry: '',
    geos_factory: @@geos_factory,
    geom_distance: 0,
    deleted: false,
    members: nil,
    version: 1,
    changesets: [@@fixture_changeset1],
    username: 'bob',
    created: 'today',
    tags: T.let({
      'foo' => 'bar',
    }, T::Hash[String, String]),
    is_change: false,
    group_ids: nil,
  )

  @@fixture_node_b = Validation::OSMChangeProperties.new(
    objtype: 'n',
    id: 1,
    geojson_geometry: '{"type":"Point","coordinates":[1,1]}',
    geos_factory: @@geos_factory,
    geom_distance: 1,
    deleted: false,
    members: nil,
    version: 2,
    changesets: [@@fixture_changeset1],
    username: 'bob',
    created: 'today',
    tags: {
      'bar' => 'foo',
    },
    is_change: true,
    group_ids: nil,
  )

  sig { void }
  def test_object_validation_before
    validation = Validation.object_validation([], @@fixture_node_a, @@fixture_node_a, nil)
    validation_result = Validation::ValidationResult.new(
      action: nil,
      changeset_ids: @@fixture_node_a.changesets&.pluck('id'),
      created: @@fixture_node_a.created,
      diff: Validation::DiffActions.new(
        attribs: {
          'deleted' => [],
          'geom' => [],
        },
        tags: { 'foo' => [] },
      ),
    )
    assert_equal(validation_result.inspect, validation.inspect)
  end

  sig { void }
  def test_object_validation_after
    validation = Validation.object_validation([], nil, nil, @@fixture_node_b)
    validation_result = Validation::ValidationResult.new(
      action: nil,
      changeset_ids: @@fixture_node_b.changesets&.pluck('id'),
      created: @@fixture_node_b.created,
      diff: Validation::DiffActions.new(
        attribs: { 'deleted' => [], 'geom' => [] },
        tags: { 'bar' => [] },
      ),
    )
    assert_equal(validation_result.inspect, validation.inspect)
  end

  sig { void }
  def test_object_validation_same
    b = @@fixture_node_a.with(is_change: true)
    validation = Validation.object_validation([], @@fixture_node_a, b, b)
    validation_result = Validation::ValidationResult.new(
      action: 'accept',
      changeset_ids: @@fixture_node_a.changesets&.pluck('id'),
      created: @@fixture_node_a.created,
      diff: Validation::DiffActions.new(
        attribs: {},
        tags: {},
      ),
    )
    assert_equal(validation_result.inspect, validation.inspect)
  end

  sig { void }
  def test_object_validation2
    validation = Validation.object_validation([], @@fixture_node_a, @@fixture_node_a, @@fixture_node_b)
    validation_result = Validation::ValidationResult.new(
      action: nil,
      changeset_ids: @@fixture_node_a.changesets&.pluck('id'),
      created: @@fixture_node_b.created,
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
        [Validators::All.new(id: id, osm_tags_matches: Osm::TagsMatches.new([]), action: action)],
        @@fixture_node_a, @@fixture_node_a, @@fixture_node_b,
      )

      validated = [Validation::Action.new(
        validator_id: id,
        action: action || 'reject',
      )]
      validation_result = Validation::ValidationResult.new(
        action: action || 'reject',
        changeset_ids: @@fixture_node_b.changesets&.pluck('id'),
        created: @@fixture_node_b.created,
        diff: Validation::DiffActions.new(
          attribs: { 'geom' => validated },
          tags: { 'foo' => validated, 'bar' => validated },
        ),
      )
      assert_equal(validation_result.inspect, validation.inspect)
    }
  end
end
