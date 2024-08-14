# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/validation/lo_cha'


class TestLoCha < Test::Unit::TestCase
  extend T::Sig

  @@demi_distance = T.let(1.0, Float) # m

  sig { void }
  def test_key_val_main_distance
    assert_equal(0.0, LoCha.key_val_main_distance({}, {}))
    assert_equal(0.0, LoCha.key_val_main_distance({ 'foo' => 'bar' }, { 'foo' => 'bar' }))
    assert_equal(1.0, LoCha.key_val_main_distance({ 'foo' => 'bar' }, {}))
    assert_equal(1.0, LoCha.key_val_main_distance({}, { 'foo' => 'bar' }))

    assert_equal(1.0, LoCha.key_val_main_distance({ 'foo' => 'a' }, { 'foo' => 'b' }))
    assert_equal(1.0, LoCha.key_val_main_distance({ 'foo' => 'a' }, { 'foo' => 'ab' }))
  end

  sig { void }
  def test_key_val_fuzzy_distance
    assert_equal(0.5, LoCha.key_val_fuzzy_distance({ 'foo' => 'a' }, { 'foo' => 'b' }))
    assert_equal(0.25, LoCha.key_val_fuzzy_distance({ 'foo' => 'a' }, { 'foo' => 'ab' }))
    assert_equal(0.25, LoCha.key_val_fuzzy_distance({ 'foo' => 'ab' }, { 'foo' => 'ac' }))
    assert_equal(1.0 / 3, LoCha.key_val_fuzzy_distance({ 'foo' => 'a' }, { 'foo' => 'abc' }))

    assert_equal(0.5, LoCha.key_val_fuzzy_distance({ 'foo' => 'a' }, { 'foo' => 'a', 'bar' => 'b' }))
  end

  sig { void }
  def test_tags_distance
    assert_equal(0.0, LoCha.tags_distance({ 'highway' => 'a' }, { 'highway' => 'a' }))
    assert_equal(0.0, LoCha.tags_distance({ 'foo' => 'a' }, { 'foo' => 'a' }))
    assert_equal(0.0, LoCha.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'highway' => 'a', 'foo' => 'a' }))
    assert_equal(0.5, LoCha.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'building' => 'a', 'foo' => 'a' }))
    assert_equal(0.5, LoCha.tags_distance({ 'highway' => 'a', 'foo' => 'a' }, { 'foo' => 'a' }))
    assert_equal(0.25, LoCha.tags_distance({ 'highway' => 'a', 'foo' => 'a', 'bar' => 'b' }, { 'highway' => 'a', 'foo' => 'a' }))
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
    before_tags: {},
    after_tags: {},
    before_geom: '{"type":"Point","coordinates":[0,0]}',
    after_geom: '{"type":"Point","coordinates":[0,0]}'
  )
    before = [T.let({
      'locha_id' => 1,
      'objtype' => 'n',
      'id' => 1,
      'geom' => JSON.parse(before_geom),
      'geom_distance' => 0,
      'deleted' => false,
      'members' => nil,
      'version' => 1,
      'changesets' => nil,
      'username' => 'bob',
      'created' => 'today',
      'tags' => before_tags,
      'is_change' => false,
      'group_ids' => nil,
    }, Validation::OSMChangeProperties)]

    after = [T.let({
      'locha_id' => 1,
      'objtype' => 'n',
      'id' => 1,
      'geom' => JSON.parse(after_geom),
      'geom_distance' => 0,
      'deleted' => false,
      'members' => nil,
      'version' => 1,
      'changesets' => nil,
      'username' => 'bob',
      'created' => 'today',
      'tags' => after_tags,
      'is_change' => true,
      'group_ids' => nil,
    }, Validation::OSMChangeProperties)]

    [before, after]
  end

  sig { void }
  def test_conflate_tags
    before, after = build_objects(before_tags: { 'highway' => 'a' }, after_tags: { 'highway' => 'a' })
    assert_equal(LoCha.conflate(before, after, @@demi_distance), [[before[0], after[0], after[0]]])

    before, after = build_objects(before_tags: { 'foo' => 'a' }, after_tags: { 'foo' => 'b' })
    assert_equal(LoCha.conflate(before, after, @@demi_distance), [[before[0], after[0], after[0]]])

    before, after = build_objects(before_tags: { 'highway' => 'a' }, after_tags: { 'building' => 'b' })
    assert_equal(LoCha.conflate(before, after, @@demi_distance), [[before[0], after[0], nil], [nil, nil, after[0]]])

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

    assert(LoCha.tags_distance(bt, at) < 0.5)
    assert_equal(LoCha.conflate(before, after, @@demi_distance), [[before[0], after[0], after[0]]])
  end

  sig { void }
  def test_conflate_geom
    before, after = build_objects(before_geom: '{"type":"Point","coordinates":[0,0]}', after_geom: '{"type":"Point","coordinates":[0,1]}')
    assert_equal(0.5, LoCha.geom_distance(
      T.must(before[0])['geom'],
      T.must(after[0])['geom'],
      @@demi_distance
    ))
    assert_equal(LoCha.conflate(before, after, @@demi_distance), [[before[0], after[0], after[0]]])

    before, after = build_objects(before_geom: '{"type":"LineString","coordinates":[[0,0],[1,0]]}', after_geom: '{"type":"LineString","coordinates":[[0,0],[0,1]]}')
    assert_equal(0.5, LoCha.geom_distance(
      T.must(before[0])['geom'],
      T.must(after[0])['geom'],
      @@demi_distance
    ))
    assert_equal(LoCha.conflate(before, after, @@demi_distance), [[before[0], after[0], after[0]]])

    before, after = build_objects(before_geom: '{"type":"LineString","coordinates":[[0,0],[0,1]]}', after_geom: '{"type":"LineString","coordinates":[[0,2],[0,3]]}')
    assert_equal(0.75, LoCha.geom_distance(
      T.must(before[0])['geom'],
      T.must(after[0])['geom'],
      @@demi_distance
    ))
    assert_equal(LoCha.conflate(before, after, @@demi_distance), [[before[0], after[0], after[0]]])
  end
end
