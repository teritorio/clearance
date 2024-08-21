# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'rgeo/geo_json'

module DistanceHausdorff
  extend T::Sig

  sig {
    params(
      geom1: RGeo::Feature::Geometry,
      geom2: RGeo::Feature::Geometry,
    ).returns(Float)
  }
  def self.distance(geom1, geom2)
    points1 = points(geom1)
    points2 = points(geom2)

    return 0.0 if points1.size >= 16 || points2.size >= 16

    max = 0.0
    points1.each { |pp1|
      min = Float::INFINITY
      points2.each { |pp2|
        min = [min, T.cast(pp1.distance(pp2), Float)].min
      }
      max = [max, min].max
    }
    max
  end

  sig {
    params(
      geom: RGeo::Feature::Geometry,
    ).returns(T::Array[RGeo::Feature::Point])
  }
  def self.points(geom)
    # Check if geom is a multi or collection
    if geom.geometry_type.type_name.start_with?('Multi') || geom.geometry_type.type_name == 'GeometryCollection'
      T.unsafe(geom).collect{ |sub| points(sub) }.flatten
    elsif geom.geometry_type.type_name == 'Point'
      [geom]
    elsif geom.geometry_type.type_name == 'LineString'
      T.cast(geom, RGeo::Feature::LineString).points
    elsif geom.geometry_type.type_name == 'Polygon'
      poly = T.cast(geom, RGeo::Feature::Polygon)
      poly.exterior_ring.points + poly.interior_rings.collect(&:points).flatten
    else
      raise 'Unsupported geometry type'
    end
  end
end
