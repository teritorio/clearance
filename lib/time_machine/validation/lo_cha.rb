# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'levenshtein'
require 'set'
require 'rgeo'
require 'rgeo/geo_json'
require 'rgeo/proj4'
require './lib/time_machine/validation/changes_db'

module LoCha
  extend T::Sig

  MAIN_TAGS = T.let(Set.new(%w[highway railway waterway aeroway amenity landuse leisure]), T::Set[String])

  sig {
    params(
      tags_a: T::Hash[String, String],
      tags_b: T::Hash[String, String],
    ).returns(T.nilable(Float))
  }
  def self.key_val_main_distance(tags_a, tags_b)
    return nil if tags_a.empty? && tags_b.empty?
    return 1.0 if tags_a.empty? || tags_b.empty?

    ka = tags_a.collect { |k, v| "#{k}=#{v}" }
    kb = tags_b.collect { |k, v| "#{k}=#{v}" }
    1 - (ka & kb).size.to_f / (ka | kb).size
  end

  sig {
    params(
      tags_a: T::Hash[String, String],
      tags_b: T::Hash[String, String],
    ).returns(Float)
  }
  def self.key_val_fuzzy_distance(tags_a, tags_b)
    return 0.0 if tags_a.empty? && tags_b.empty?
    return 1.0 if tags_a.empty? || tags_b.empty?

    all_keys_size = (tags_a.keys | tags_b.keys).size
    commons_keys = tags_a.keys & tags_b.keys
    (commons_keys.collect{ |key|
      (Levenshtein.ffi_distance(tags_a[key], tags_b[key]).to_f / [T.must(tags_a[key]), T.must(tags_b[key])].collect(&:size).max).clamp(0, 1) / 2
    }.sum.to_f + (all_keys_size - commons_keys.size)) / all_keys_size
  end

  sig {
    params(
      tags_a: T::Hash[String, String],
      tags_b: T::Hash[String, String],
    ).returns(T.nilable(Float))
  }
  def self.tags_distance(tags_a, tags_b)
    a, b = [tags_a, tags_b].collect{ |tags|
      tags.partition{ |k, _v| MAIN_TAGS.include?(k) }.collect(&:to_h)
    }

    # Main tags
    d_main = key_val_main_distance(T.must(a)[0] || {}, T.must(b)[0] || {})
    return if d_main.nil?

    # Other tags
    (d_main + key_val_fuzzy_distance(T.must(a)[1] || {}, T.must(b)[1] || {})) / 2
  end

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
      geom_a: T.nilable(T::Hash[String, T.untyped]),
      geom_b: T.nilable(T::Hash[String, T.untyped]),
      demi_distance: Float,
      decode: T.proc.params(arg0: T::Hash[String, T.untyped]).returns(RGeo::Feature::Geometry),
    ).returns(T.nilable(Float))
  }
  def self.geom_distance(geom_a, geom_b, demi_distance, decode = ->(geom) { RGeo::GeoJSON.decode(geom) })
    return nil if geom_a.nil? || geom_b.nil?
    return 0.0 if geom_a == geom_b

    begin
      r_geom_a = decode.call(geom_a)
      r_geom_b = decode.call(geom_b)
    rescue StandardError
      return nil
    end
    return 0.0 if r_geom_a.equals?(r_geom_b)

    if r_geom_a.intersects?(r_geom_b)
      dim_a = r_geom_a.dimension
      if dim_a != r_geom_b.dimension ||
         r_geom_a.buffer(geom_diameter(r_geom_a) * 0.05).contains?(r_geom_b) ||
         r_geom_b.buffer(geom_diameter(r_geom_b) * 0.05).contains?(r_geom_a)
        0.0
      elsif dim_a == 1
        r_geom_a.sym_difference(r_geom_b).length / r_geom_a.union(r_geom_b).length / 2
      elsif dim_a == 2
        r_geom_a.sym_difference(r_geom_b).area / r_geom_a.union(r_geom_b).area / 2
      end
    elsif r_geom_a.dimension == 0 && r_geom_b.dimension == 0
      d = log_distance(r_geom_a, r_geom_b, demi_distance)
      d > 0.5 ? nil : d * 2
    else
      0.5 + log_distance(r_geom_a, r_geom_b, demi_distance) / 2
    end
  end

  Conflations = T.type_alias {
    T::Array[[
      T.nilable(Validation::OSMChangeProperties),
      T.nilable(Validation::OSMChangeProperties),
      T.nilable(Validation::OSMChangeProperties)
    ]]
  }

  sig {
    params(
      before: Validation::OSMChangeProperties,
      after: Validation::OSMChangeProperties,
      demi_distance: Float,
      geom_cache: T::Hash[T::Hash[String, T.untyped], RGeo::Feature::Geometry],
      geo_factory: T.untyped,
      projection: T.untyped,
    ).returns(T.nilable([Float, Float, Float]))
  }
  def self.vect_dist(before, after, demi_distance, geom_cache, geo_factory, projection)
    t_dist = tags_distance(before['tags'], after['tags'])
    return if t_dist.nil? || t_dist >= 0.5

    g_dist = geom_distance(before['geom'], after['geom'], demi_distance, lambda { |geom|
      geom_cache[geom] ||= RGeo::Feature.cast(
        RGeo::GeoJSON.decode(geom, geo_factory: geo_factory),
        project: true,
        factory: projection,
      )
      geom_cache[geom]
    })
    return if g_dist.nil?

    [
      t_dist,
      g_dist,
      (before['objtype'] == after['objtype'] && before['id'] == after['id'] ? 0.0 : 0.000001),
    ]
  end

  sig {
    params(
      befores: T::Array[Validation::OSMChangeProperties],
      afters: T::Array[Validation::OSMChangeProperties],
      local_srid: Integer,
      demi_distance: Float,
    ).returns(T::Hash[[Validation::OSMChangeProperties, Validation::OSMChangeProperties], [Float, Float, Float]])
  }
  def self.conflate_matrix(befores, afters, local_srid, demi_distance)
    distance_matrix = T.let({}, T::Hash[[Validation::OSMChangeProperties, Validation::OSMChangeProperties], [Float, Float, Float]])
    min = 3.0
    geom_cache = T.let({}, T::Hash[T::Hash[String, T.untyped], RGeo::Feature::Geometry])
    geo_factory = RGeo::Geos.factory(srid: 4326)
    projection = RGeo::Geos.factory(srid: local_srid)
    befores.each{ |b|
      afters.each{ |a|
        v = vect_dist(b, a, demi_distance, geom_cache, geo_factory, projection)
        if !v.nil?
          distance_matrix[[b, a]] = v
          s = v.sum
          min = s if s < min
        end
      }
    }

    distance_matrix
  end

  sig {
    params(
      befores: T::Array[Validation::OSMChangeProperties],
      afters: T::Array[Validation::OSMChangeProperties],
      local_srid: Integer,
      demi_distance: Float,
    ).returns(Conflations)
  }
  def self.conflate(befores, afters, local_srid, demi_distance)
    distance_matrix = conflate_matrix(befores, afters, local_srid, demi_distance)

    afters_index = afters.index_by{ |a| [a['objtype'], a['id']] }
    paired = T.let([], Conflations)
    paired_befores = T.let([], T::Array[Validation::OSMChangeProperties])
    paired_afters = T.let([], T::Array[Validation::OSMChangeProperties])
    until distance_matrix.empty?
      key_min = T.must(distance_matrix.to_a.min_by{ |_keys, coefs| coefs.sum }).first
      paired << [key_min[0], afters_index[[key_min[0]['objtype'], key_min[0]['id']]], key_min[1]]
      paired_befores << key_min.first
      paired_afters << key_min.last

      min = 3.0
      distance_matrix = distance_matrix.select{ |k, v|
        r = (k & key_min).empty?
        s = v.sum
        min = s if s < min
        r
      }
    end

    paired = T.cast(paired + (befores - paired_befores).collect{ |b| [b, afters_index[[b['objtype'], b['id']]], nil] }, Conflations)
    T.cast(paired + (afters - paired_afters).collect{ |a| [nil, nil, a] }, Conflations)
  end
end
