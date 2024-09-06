# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'rgeo'


module LogicalHistory
  module Geom
    extend T::Sig

    sig {
      params(
        geom: RGeo::Feature::Geometry,
      ).returns(Float)
    }
    def self.geom_diameter(geom)
      ring = geom.envelope.exterior_ring
      ring.point_n(0).distance(ring.point_n(2))
    end

    sig {
      params(
        geom_a: RGeo::Feature::Geometry,
        geom_b: RGeo::Feature::Geometry,
        demi_distance: Float,
      ).returns(Float)
    }
    def self.log_distance(geom_a, geom_b, demi_distance)
      distance = geom_a.distance(geom_b)
      # 0.0 -> 0.0
      # demi_distance -> 0.5
      # infinite -> 1.0
      1.0 - 1.0 / (distance / demi_distance + 1.0)
    end

    sig {
      params(
        r_geom_a: RGeo::Feature::Geometry,
        r_geom_b: RGeo::Feature::Geometry,
        a_over_b: RGeo::Feature::Geometry,
        b_over_a: RGeo::Feature::Geometry,
        union: RGeo::Feature::Geometry,
        _block: T.proc.params(arg0: RGeo::Feature::Geometry).returns(Float),
      ).returns([Float, T.nilable(RGeo::Feature::Geometry), T.nilable(RGeo::Feature::Geometry)])
    }
    def self.exact_or_buffered_size_over_union(r_geom_a, r_geom_b, a_over_b, b_over_a, union, &_block)
      buffered_distance = (yield(a_over_b) + yield(b_over_a)) / yield(union) / 2

      if r_geom_a.intersection(r_geom_b).dimension < r_geom_a.dimension
        # Excact distance give a lower dimension geom, use buffered distance
        return [buffered_distance, a_over_b.empty? ? nil : a_over_b, b_over_a.empty? ? a_over_b : nil]
      end

      exact_a_over_b = r_geom_a - r_geom_b
      exact_b_over_a = r_geom_b - r_geom_a
      exact_distance = (yield(exact_a_over_b) + yield(exact_b_over_a)) / yield(union) / 2

      # Prefer exact distance if it's more than 60% of the buffered distance
      if exact_distance / buffered_distance > 0.6
        [exact_distance, exact_a_over_b.empty? ? nil : exact_a_over_b, exact_b_over_a.empty? ? nil : exact_b_over_a]
      else
        [buffered_distance, a_over_b.empty? ? nil : a_over_b, b_over_a.empty? ? b_over_a : nil]
      end
    end

    sig {
      params(
        r_geom_a: RGeo::Feature::Geometry,
        r_geom_b: RGeo::Feature::Geometry,
        demi_distance: Float,
      ).returns(T.nilable([Float, T.nilable(RGeo::Feature::Geometry), T.nilable(RGeo::Feature::Geometry)]))
    }
    def self.geom_distance(r_geom_a, r_geom_b, demi_distance)
      return [0.0, nil, nil] if r_geom_a.equals?(r_geom_b)

      if r_geom_a.dimension == 0 && r_geom_b.dimension == 0
        # Point never intersects, unless they are the same
        d = log_distance(r_geom_a, r_geom_b, demi_distance)
        return d <= 0.5 ? [d * 2, nil, nil] : nil
      end

      intersection = r_geom_a.intersection(r_geom_b)

      # Ensure inner intersection (crossing) not just touching
      if !intersection.empty? && intersection.dimension == r_geom_a.dimension && intersection.dimension == r_geom_b.dimension
        # Compute: 1 - intersection / union
        # Compute buffered symetrical difference
        a_over_b = T.let(r_geom_a - r_geom_b.buffer(geom_diameter(r_geom_b) * 0.05), RGeo::Feature::Geometry)
        b_over_a = T.let(r_geom_b - r_geom_a.buffer(geom_diameter(r_geom_a) * 0.05), RGeo::Feature::Geometry)

        if a_over_b.empty? || b_over_a.empty?
          # One subpart of the other
          union = r_geom_a.union(r_geom_b)
          parts = exact_or_buffered_size_over_union(r_geom_a, r_geom_b, a_over_b, b_over_a, union) { |geom|
            intersection.dimension == 1 ? T.unsafe(geom).length : T.unsafe(geom).area
          }
          [0.0, parts[1], parts[2]]
        else
          dim_a = a_over_b.dimension
          dim_b = b_over_a.dimension
          union = r_geom_a.union(r_geom_b)
          dim_union = union.dimension
          if dim_a == 0 && dim_b == 0 && dim_union == 0
            # Points
            raise 'Non equal intersecting points, should never happen.'
          elsif dim_a == 1 && dim_b == 1 && dim_union == 1
            # Lines
            exact_or_buffered_size_over_union(r_geom_a, r_geom_b, a_over_b, b_over_a, union) { |geom| T.unsafe(geom).length }
          elsif dim_a == 2 && dim_b == 2 && dim_union == 2
            exact_or_buffered_size_over_union(r_geom_a, r_geom_b, a_over_b, b_over_a, union) { |geom| T.unsafe(geom).area }
          else
            raise 'Diff dimension geom should not happen.'
          end
        end
      else
        # Else, use real distance + bias because no intersection
        d = 0.5 + log_distance(r_geom_a, r_geom_b, demi_distance) / 2
        [d, nil, nil]
      end
    end
  end
end
