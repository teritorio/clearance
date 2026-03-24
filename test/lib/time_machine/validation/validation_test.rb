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

  sig {
    params(
      before: T.nilable(Validation::OSMChangeProperties),
      before_at_now: T.nilable(Validation::OSMChangeProperties),
      after: T.nilable(Validation::OSMChangeProperties),
    ).returns(T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]])
  }
  def build_clusters(before, before_at_now, after)
    conflation = OSMLogicalHistory::Conflation::ConflationNilableOnly[Validation::OSMChangeProperties].new(
      before: before,
      before_at_now: before_at_now,
      after: after,
      conflation_reason: OSMLogicalHistory::Conflation::ConflationReason.new(conflate: '')
    )
    T.let([[[], [Validation::Link.new(
      conflation: conflation,
      validations: [],
      result: Validation::ValidationResult.new(
        action: 'accept',
        changeset_ids: T.must(conflation.after || conflation.before_at_now).changesets&.pluck('id'),
        created: T.must(conflation.after || conflation.before_at_now).created,
        diff: Validation.diff_osm_object(conflation.before, conflation.after),
      ),
    )]]], T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]])
  end

  sig {
    params(
      validators: T::Array[Validators::ValidatorBase],
      prevalidation_clusters: T::Array[[T::Array[Validation::Link], T::Array[Validation::Link]]],
    ).returns(Validation::ValidationResult)
  }
  def validate(validators, prevalidation_clusters)
    a = Validation.time_machine_validate(nil, @@srid, validators, prevalidation_clusters).first&.last
    T.must(a&.first&.result)
  end

  sig { void }
  def test_object_validation_before
    clusters = build_clusters(@@fixture_node_a, @@fixture_node_a, nil)
    validation = validate([], clusters)
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
    clusters = build_clusters(nil, nil, @@fixture_node_b)
    validation = validate([], clusters)
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
    clusters = build_clusters(@@fixture_node_a, b, b)
    validation = validate([], clusters)
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
    clusters = build_clusters(@@fixture_node_a, @@fixture_node_a, @@fixture_node_b)
    validation = validate([], clusters)
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
      clusters = build_clusters(@@fixture_node_a, @@fixture_node_a, @@fixture_node_b)
      validation = validate(
        [Validators::All.new(settings: Validators::ValidatorBase::Settings.new(id: id, config: nil, osm_tags_matches: Osm::TagsMatches.new([]), description: nil), action: action)],
        clusters
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
