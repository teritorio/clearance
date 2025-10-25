# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/logical_history/geom'

Geom = LogicalHistory::Geom

class TestLoCha < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_geom_distance
    srid = 2154
    demi_distance = 200.0 # m

    geo_factory = RGeo::Geos.factory(srid: 4326)
    projection = RGeo::Geos.factory(srid: srid)

    before = RGeo::Feature.cast(
      RGeo::GeoJSON.decode({ 'type' => 'Point', 'coordinates' => [-1.4865344, 43.5357032] }, geo_factory: geo_factory),
      project: true,
      factory: projection,
    )
    after = RGeo::Feature.cast(
      RGeo::GeoJSON.decode({ 'type' => 'Point', 'coordinates' => [-1.4864637, 43.5359501] }, geo_factory: geo_factory),
      project: true,
      factory: projection,
    )
    d = Geom.geom_score(before, after, demi_distance)

    assert(T.must(d&.first) < 0.5)
    assert(T.must(d&.first) > 0.0)
  end
end
