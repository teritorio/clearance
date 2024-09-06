# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/logical_history/conflation'
require './lib/time_machine/logical_history/tags'
require './lib/time_machine/logical_history/geom'

Conflation = LogicalHistory::Conflation

class TestConflation < Test::Unit::TestCase
  extend T::Sig

  @@srid = T.let(4326, Integer) # No projection
  @@demi_distance = T.let(1.0, Float) # m

  sig {
    params(
      id: Integer,
      version: Integer,
      tags: T::Hash[String, String],
      geom: String,
    ).returns(Validation::OSMChangeProperties)
  }
  def build_object(
    id: 1,
    version: 1,
    tags: { 'highway' => 'a' },
    geom: '{"type":"Point","coordinates":[0,0]}'
  )
    Validation::OSMChangeProperties.new(
        locha_id: 1,
        objtype: 'n',
        id: id,
        geom: '',
        geos: RGeo::GeoJSON.decode(JSON.parse(geom)),
        geom_distance: 0,
        deleted: false,
        members: nil,
        version: version,
        changesets: nil,
        username: 'bob',
        created: 'today',
        tags: tags,
        is_change: false,
        group_ids: nil,
      )
  end

  sig {
    params(
      before_tags: T::Hash[String, String],
      after_tags: T::Hash[String, String],
      before_geom: String,
      after_geom: String,
    ).returns([T::Array[Validation::OSMChangeProperties], T::Array[Validation::OSMChangeProperties]])
  }
  def build_objects(
    before_tags: { 'highway' => 'a' },
    after_tags: { 'highway' => 'a' },
    before_geom: '{"type":"Point","coordinates":[0,0]}',
    after_geom: '{"type":"Point","coordinates":[0,0]}'
  )
    before = [build_object(id: 1, tags: before_tags, geom: before_geom)]
    after = [build_object(id: 1, tags: after_tags, geom: after_geom)]
    [before, after]
  end

  sig { void }
  def test_conflate_refs
    before, after = build_objects(before_tags: { 'ref' => 'a' }, after_tags: { 'ref' => 'a' })
    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )

    before, after = build_objects(before_tags: { 'ref' => 'a', 'foo' => 'a' }, after_tags: { 'ref' => 'a', 'foo' => 'b' })
    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )

    before, after = build_objects(before_tags: { 'ref' => 'a' }, after_tags: { 'ref' => 'b' })
    assert_equal(
      [[before[0], after[0], nil], [nil, nil, after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )
  end

  sig { void }
  def test_conflate_tags
    before, after = build_objects(before_tags: { 'highway' => 'a' }, after_tags: { 'highway' => 'a' })
    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )

    before, after = build_objects(before_tags: { 'highway' => 'a', 'foo' => 'a' }, after_tags: { 'highway' => 'a', 'foo' => 'b' })
    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )

    before, after = build_objects(before_tags: { 'highway' => 'a' }, after_tags: { 'building' => 'b' })
    assert_equal(
      [[before[0], after[0], nil], [nil, nil, after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )

    bt = {
      'name' => 'Utopia',
      'brand' => 'Utopia',
      'screen' => '4',
      'amenity' => 'cinema',
      'roof:shape' => 'gabled',
      'addr:street' => 'Rue du Moulinet',
      'brand:wikidata' => 'Q3552766',
      'addr:housenumber' => '11',
      'phone' => '+33 (0) 3 25 40 52 90',
    }
    at = bt.merge({
      'phone' => '+33 3 25 40 52 90',
      'addr:city' => 'Pont-Sainte-Marie',
      'addr:postcode' => '10150',
    }).compact
    before, after = build_objects(before_tags: bt, after_tags: at)

    assert(T.must(LogicalHistory::Tags.tags_distance(bt, at)) < 0.5)
    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )
  end

  sig { void }
  def test_conflate_geom
    before, after = build_objects(before_geom: '{"type":"Point","coordinates":[0,0]}', after_geom: '{"type":"Point","coordinates":[0,1]}')
    assert_equal(1.0, LogicalHistory::Geom.geom_distance(
      T.must(before[0]&.geos),
      T.must(after[0]&.geos),
      @@demi_distance
    )&.first)
    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )

    before, after = build_objects(before_geom: '{"type":"LineString","coordinates":[[0,0],[1,0]]}', after_geom: '{"type":"LineString","coordinates":[[0,0],[0,1]]}')
    assert_equal(0.5, LogicalHistory::Geom.geom_distance(
      T.must(before[0]&.geos),
      T.must(after[0]&.geos),
      @@demi_distance
    )&.first)
    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )

    before, after = build_objects(before_geom: '{"type":"LineString","coordinates":[[0,0],[0,1]]}', after_geom: '{"type":"LineString","coordinates":[[0,2],[0,3]]}')
    assert_equal(0.75, LogicalHistory::Geom.geom_distance(
      T.must(before[0]&.geos),
      T.must(after[0]&.geos),
      @@demi_distance
    )&.first)
    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )
  end

  sig { void }
  def test_conflate_deleted
    tags = { 'highway' => 'residential' }
    geom = '{"type":"Point","coordinates":[0,0]}'
    before = [
      build_object(id: 1, geom: geom, tags: tags),
    ]
    after = [
      build_object(id: 1, geom: geom, tags: tags).with(deleted: true),
      build_object(id: 2, geom: geom, tags: tags),
    ]

    conflations = Conflation.conflate(before, after, @@srid, @@demi_distance)
    assert_equal(1, conflations.size, conflations)
    assert_equal([[before[0], after[0], after[1]]], conflations.collect(&:to_a))
  end

  sig { void }
  def test_conflate_semantic_deleted
    geom = '{"type":"Point","coordinates":[0,0]}'
    before = [
      build_object(id: 1, geom: geom, tags: { 'highway' => 'residential' }),
    ]
    after = [
      build_object(id: 1, geom: geom, tags: {}),
      build_object(id: 2, geom: geom, tags: { 'highway' => 'residential' }),
    ]

    conflations = Conflation.conflate(before, after, @@srid, @@demi_distance)
    assert_equal(2, conflations.size, conflations)
    assert_equal([[before[0], after[0], after[1]], [nil, nil, after[0]]], conflations.collect(&:to_a))
  end

  sig { void }
  def test_conflate_tags_geom_not_tag_comparable
    before, after = build_objects(
      before_tags: { 'amenity' => 'bicycle_parking' },
      before_geom: '{"type":"Point","coordinates":[0, 0]}',
      after_tags: { 'amenity' => 'parking' },
      after_geom: '{"type":"Point","coordinates":[0, 0]}'
    )
    assert_equal(nil, LogicalHistory::Tags.tags_distance(T.must(before[0]).tags, T.must(after[0]).tags))
    conflate_distances = Conflation.conflate_matrix(before.to_set, after.to_set, @@srid, @@demi_distance).first
    assert_equal({}, conflate_distances)
    assert_equal(
      [[before[0], after[0], nil], [nil, nil, after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )
  end

  sig { void }
  def test_conflate_tags_geom_too_large_distance
    before, after = build_objects(
      before_tags: { 'amenity' => 'bicycle_parking' },
      before_geom: '{"type":"Point","coordinates":[0, 0]}',
      after_tags: { 'amenity' => 'bicycle_parking' },
      after_geom: '{"type":"Point","coordinates":[0, 2]}'
    )
    assert_equal(0.0, LogicalHistory::Tags.tags_distance(T.must(before[0]).tags, T.must(after[0]).tags))
    conflate_distances = Conflation.conflate_matrix(before.to_set, after.to_set, @@srid, @@demi_distance).first
    assert_equal({}, conflate_distances)
    assert_equal(
      [[before[0], after[0], nil], [nil, nil, after[0]]],
      Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a)
    )
  end

  sig { void }
  def test_conflate_tags_geom
    before, after = build_objects(
      before_tags: { 'amenity' => 'bicycle_parking' },
      before_geom: '{"type":"Point","coordinates":[0, 0]}',
      after_tags: { 'amenity' => 'bicycle_parking' },
      after_geom: '{"type":"Point","coordinates":[0, 0.5]}'
    )
    assert_equal(0.0, LogicalHistory::Tags.tags_distance(T.must(before[0]).tags, T.must(after[0]).tags))
    conflate_distances = Conflation.conflate_matrix(before.to_set, after.to_set, @@srid, @@demi_distance).first
    assert_equal([[before[0], after[0]]], conflate_distances.keys)
    assert_equal(0.0, T.must(conflate_distances.values[0])[0])
    assert_equal(0.0, T.must(conflate_distances.values[0])[2])
    assert_equal([[before[0], after[0], after[0]]], Conflation.conflate(before, after, @@srid, @@demi_distance).collect(&:to_a))
  end

  sig { void }
  def test_conflate_no_comparable_tags
    srid = 23_031 # UTM zone 31N, 0°E
    demi_distance = 200.0 # m

    before, after = build_objects(
      before_tags: { 'building' => 'retail' },
      before_geom: '{"type":"Point","coordinates":[28.10176, -15.44687]}',
      after_tags: { 'building' => 'yes', 'building:levels' => '13' },
      after_geom: '{"type":"Point","coordinates":[28.10128, -15.44647]}'
    )
    conflate_distances = Conflation.conflate_matrix(before.to_set, after.to_set, srid, demi_distance).first
    assert_equal([], conflate_distances.keys)
    assert_equal([[before[0], after[0], nil], [nil, nil, after[0]]], Conflation.conflate(before, after, srid, demi_distance).collect(&:to_a))
  end

  sig { void }
  def test_conflate_double
    srid = 2154
    demi_distance = 200.0 # m

    before_tags = {
      'bus' => 'yes',
      'highway' => 'bus_stop',
      'name' => 'Guyenne',
      'operator' => 'Chronoplus',
      'public_transport' => 'platform',
    }
    before = [
      build_object(id: 1, geom: '{"type":"Point","coordinates":[-1.4865344, 43.5357032]}', tags: before_tags),
      build_object(id: 2, geom: '{"type":"Point","coordinates":[-1.4864637, 43.5359501]}', tags: before_tags),
    ]

    after_tags = {
      'bench' => 'no',
      'bus' => 'yes',
      'highway' => 'bus_stop',
      'name' => 'Guyenne',
      'network' => 'Txik Txak',
      'operator' => 'Chronoplus',
      'public_transport' => 'platform',
      'shelter' => 'no',
    }
    after = [
      build_object(id: 1, geom: '{"type":"Point","coordinates":[-1.4865344, 43.5357032]}', tags: after_tags),
      build_object(id: 2, geom: '{"type":"Point","coordinates":[-1.4864637, 43.5359501]}', tags: after_tags),
    ]

    conflate_distances = Conflation.conflate_matrix(before.to_set, after.to_set, srid, demi_distance).first
    assert_equal(4, conflate_distances.keys.size)
    assert_equal(
      [[before[0], after[0], after[0]], [before[1], after[1], after[1]]],
      Conflation.conflate(before, after, srid, demi_distance).collect(&:to_a)
    )
  end

  sig { void }
  def test_conflate_polygon
    srid = 2154
    demi_distance = 200.0 # m

    geojson = '{"type":"Polygon","coordinates":[[[-1.102128,43.543789],[-1.102262,43.543822],[-1.102333,43.543663],[-1.102197,43.54363],[-1.102128,43.543789]]]}'

    before_tags = {
      'tourism' => 'information',
      'opening_hours' => 'Mo-Sa 09:30-13:00,14:30-18:00',
    }
    before = [
      build_object(id: 1, geom: geojson, tags: before_tags),
    ]

    after_tags = {
      'tourism' => 'information',
      'opening_hours' => 'Mo-Sa 09:30-13:00,14:30-18:00; PH 10:00-13:00',
    }
    after = [
      build_object(id: 1, geom: geojson, tags: after_tags),
    ]

    assert_equal(
      [[before[0], after[0], after[0]]],
      Conflation.conflate(before, after, srid, demi_distance).collect(&:to_a)
    )
  end

  sig { void }
  def test_conflate_splited_way
    tags = {
      'highway' => 'residential',
    }
    before = [
      build_object(id: 1, geom: '{"type":"LineString","coordinates":[[0,0],[0,2]]}', tags: tags),
    ]
    after = [
      build_object(id: 1, geom: '{"type":"LineString","coordinates":[[0,0],[0,2]]}', tags: tags).with(deleted: true),
      build_object(id: 2, geom: '{"type":"LineString","coordinates":[[0,0],[0,1]]}', tags: tags),
      build_object(id: 3, geom: '{"type":"LineString","coordinates":[[0,1],[0,2]]}', tags: tags),
    ]

    conflations = Conflation.conflate(before, after, @@srid, @@demi_distance)
    assert_equal(2, conflations.size, conflations)
    assert_equal(
      [[before[0], after[0], after[1]], [before[0], after[0], after[2]]].collect{ |t| t.collect(&:id) },
      conflations.collect(&:to_a).collect{ |t| t.collect{ |k| k&.id } }
    )
  end

  sig { void }
  def test_conflate_merge_duplicate
    before = [
      build_object(
        id: 1,
        geom: '{"type": "LineString", "coordinates": [[-1.421862006187439, 43.72491455078125], [-1.421954035758972, 43.72502899169922], [-1.422500014305115, 43.72486877441406], [-1.422412037849426, 43.72471237182617], [-1.421862006187439, 43.72491455078125]]}',
        tags: { 'amenity' => 'parking' }
      ),
    ]
    after = [
      build_object(
        id: 1,
        geom: '{"type": "LineString", "coordinates": [[-1.421862006187439, 43.72491455078125], [-1.421954035758972, 43.72502899169922], [-1.422500014305115, 43.72486877441406], [-1.422412037849426, 43.72471237182617], [-1.422093033790588, 43.724788665771484], [-1.422013998031616, 43.72474670410156], [-1.421862006187439, 43.72491455078125]]}',
        tags: { 'fee' => 'no', 'access' => 'yes', 'amenity' => 'parking', 'parking' => 'surface' }
      )
    ]

    conflation = Conflation.conflate(before, after, @@srid, @@demi_distance)
    assert_equal(1, conflation.size, conflation)
    assert_equal(
      [[before[0], after[0], after[0]]].collect{ |t| t.collect(&:id) },
      conflation.collect(&:to_a).collect{ |t| t.collect{ |k| k&.id } }
    )
  end

  sig { void }
  def test_conflate_merge_remeaning
    tags = {
      'highway' => 'residential',
    }
    before = [
      build_object(id: 1, geom: '{"type":"LineString","coordinates":[[0,0],[0,2]]}', tags: tags),
    ]
    after = [
      build_object(id: 1, geom: '{"type":"LineString","coordinates":[[0,0],[0,1]]}', tags: tags),
    ]

    conflations = Conflation.conflate(before, after, @@srid, @@demi_distance)
    assert_equal(1, conflations.size, conflations)
    assert_equal(
      [[before[0], after[0], after[0]]].collect{ |t| t.collect(&:id) },
      conflations.collect(&:to_a).collect{ |t| t.collect{ |k| k&.id } }
    )
  end
end
