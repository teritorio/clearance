# frozen_string_literal: true
# typed: false

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/validation/distance_hausdorff'


class TestDistanceHausdorff < Test::Unit::TestCase
  extend T::Sig

  @@factory = T.let(RGeo::Cartesian.preferred_factory, RGeo::Feature::Factory::Instance)

  sig { void }
  def test_distance_between_two_points
    point1 = @@factory.point(0, 0)
    point2 = @@factory.point(3, 4)
    assert_in_delta(Math.sqrt(3 * 3 + 4 * 4), DistanceHausdorff.distance(point1, point2), 0.00001)
  end

  sig { void }
  def test_distance_between_point_and_line
    point = @@factory.point(0, 0)
    line = @@factory.line_string([@@factory.point(1, 0), @@factory.point(1, 1)])
    assert_in_delta(1.0, DistanceHausdorff.distance(point, line), 0.00001)
  end

  sig { void }
  def test_distance_between_two_lines
    line1 = @@factory.line_string([@@factory.point(0, 0), @@factory.point(1, 1)])
    line2 = @@factory.line_string([@@factory.point(1, 0), @@factory.point(2, 1)])
    assert_in_delta(1.0, DistanceHausdorff.distance(line1, line2), 0.00001)
  end

  sig { void }
  def test_distance_between_line_and_polygon
    line = @@factory.line_string([@@factory.point(0, 0), @@factory.point(1, 1)])
    polygon = @@factory.polygon(@@factory.linear_ring([@@factory.point(2, 2), @@factory.point(2, 3), @@factory.point(3, 3), @@factory.point(3, 2), @@factory.point(2, 2)]))
    assert_in_delta(Math.sqrt(2 * 2 + 2 * 2), DistanceHausdorff.distance(line, polygon), 0.00001)
  end

  sig { void }
  def test_distance_between_two_polygons
    polygon1 = @@factory.polygon(@@factory.linear_ring([@@factory.point(0, 0), @@factory.point(0, 1), @@factory.point(1, 1), @@factory.point(1, 0), @@factory.point(0, 0)]))
    polygon2 = @@factory.polygon(@@factory.linear_ring([@@factory.point(2, 2), @@factory.point(2, 3), @@factory.point(3, 3), @@factory.point(3, 2), @@factory.point(2, 2)]))
    assert_in_delta(Math.sqrt(2) * 2, DistanceHausdorff.distance(polygon1, polygon2), 0.00001)
  end
end
