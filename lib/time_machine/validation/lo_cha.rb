# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'levenshtein'
require 'set'
require 'rgeo'
require 'rgeo/geo_json'
require './lib/time_machine/validation/changes_db'

module LoCha
  extend T::Sig

  MAIN_TAGS = T.let(Set.new(%w[highway railway waterway aeroway amenity building landuse leisure]), T::Set[String])

  sig {
    params(
      tags_a: T::Hash[String, String],
      tags_b: T::Hash[String, String],
    ).returns(Float)
  }
  def self.key_val_main_distance(tags_a, tags_b)
    return 0.0 if tags_a.empty? && tags_b.empty?
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
    ).returns(Float)
  }
  def self.tags_distance(tags_a, tags_b)
    a, b = [tags_a, tags_b].collect{ |tags|
      tags.partition{ |k, _v| MAIN_TAGS.include?(k) }.collect(&:to_h)
    }

    # Main tags
    key_val_main_distance(T.must(a)[0] || {}, T.must(b)[0] || {}) / 2 +
      # Other tags
      key_val_fuzzy_distance(T.must(a)[1] || {}, T.must(b)[1] || {}) / 2
  end

  sig {
    params(
      geom_a: T.nilable(T::Hash[String, T.untyped]),
      geom_b: T.nilable(T::Hash[String, T.untyped]),
      decode: T.proc.params(arg0: T::Hash[String, T.untyped]).returns(RGeo::Feature::Geometry),
    ).returns(Float)
  }
  def self.geom_distance(geom_a, geom_b, decode = ->(geom) { RGeo::GeoJSON.decode(geom) })
    return 1.0 if geom_a.nil? || geom_b.nil?
    return 0.0 if geom_a == geom_b

    begin
      r_geom_a = decode.call(geom_a)
      r_geom_b = decode.call(geom_b)
    rescue StandardError
      return 1.0
    end
    return 0.0 if r_geom_a.equals?(r_geom_b)

    ring = (r_geom_a + r_geom_b).envelope.exterior_ring
    diameter = ring.point_n(0).distance(ring.point_n(2))
    if r_geom_a.intersects?(r_geom_b)
      dim_a = r_geom_a.dimension
      if dim_a != r_geom_b.dimension ||
         r_geom_a.buffer(diameter * 0.05).contains?(r_geom_b) ||
         r_geom_b.buffer(diameter * 0.05).contains?(r_geom_a)
        0.0
      elsif dim_a == 1
        r_geom_a.sym_difference(r_geom_b).length / r_geom_a.union(r_geom_b).length / 2
      elsif dim_a == 2
        r_geom_a.sym_difference(r_geom_b).area / r_geom_a.union(r_geom_b).area / 2
      end
    elsif r_geom_a.dimension == 0 && r_geom_b.dimension == 0
      r_geom_a.distance(r_geom_b) / diameter / 2
    else
      0.5 + (r_geom_a.distance(r_geom_b) / diameter) / 2
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
      befores: T::Array[Validation::OSMChangeProperties],
      afters: T::Array[Validation::OSMChangeProperties],
    ).returns(Conflations)
  }
  def self.conflate(befores, afters)
    distance_matrix = T.let({}, T::Hash[[Validation::OSMChangeProperties, Validation::OSMChangeProperties], [Float, Float, Float]])
    min = 3.0
    geom_cache = T.let({}, T::Hash[T::Hash[String, T.untyped], RGeo::Feature::Geometry])
    befores.collect{ |b|
      afters.collect{ |a|
        t_dist = tags_distance(b['tags'], a['tags'])
        if t_dist < 0.5
          v = distance_matrix[[b, a]] = [
            t_dist,
            geom_distance(b['geom'], a['geom'], lambda { |geom|
              geom_cache[geom] ||= RGeo::GeoJSON.decode(geom)
              geom_cache[geom]
            }),
            (b['objtype'] == a['objtype'] && b['id'] == a['id'] ? 0.0 : 0.000001),
          ]
          s = v.sum
          min = s if s < min
        end
      }.compact
    }

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
