# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'levenshtein'
require 'set'
require 'rgeo'
require 'rgeo/geo_json'
require 'rgeo/proj4'
require './lib/time_machine/validation/changes_db'
require './lib/time_machine/validation/distance_hausdorff'


module LoCha
  extend T::Sig

  # OSM main tags from https://github.com/osm-fr/osmose-backend/blob/dev/plugins/TagFix_MultipleTag.py
  # Exluding "building[:*]"
  MAIN_TAGS = T.let(Set.new(['aerialway', 'aeroway', 'amenity', 'barrier', 'boundary', 'craft', 'disc_golf', 'entrance', 'emergency', 'geological', 'highway', 'historic', 'landuse', 'leisure', 'man_made', 'military', 'natural', 'office', 'place', 'power', 'public_transport', 'railway', 'route', 'shop', 'sport', 'tourism', 'waterway', 'mountain_pass', 'traffic_sign', 'golf', 'piste:type', 'junction', 'healthcare', 'health_facility:type', 'indoor', 'club', 'seamark:type', 'attraction', 'information', 'advertising', 'ford', 'cemetery', 'area:highway', 'checkpoint', 'telecom', 'airmark']), T::Set[String])

  sig {
    params(
      tags: T::Hash[String, String],
    ).returns(T::Hash[String, String])
  }
  def self.refs(tags)
    tags.select{ |k, _v| k == 'ref' || k.start_with?('ref:') }
  end

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
      [exact_distance, exact_a_over_b.empty? ? nil : exact_a_over_b, exact_b_over_a.nil? ? nil : exact_b_over_a]
    else
      [buffered_distance, a_over_b.empty? ? nil : a_over_b, b_over_a.empty? ? a_over_b : nil]
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

    if r_geom_a.intersects?(r_geom_b)
      # Compute: 1 - intersection / union
      # Compute buffered symetrical difference
      a_over_b = T.let(r_geom_a - r_geom_b.buffer(geom_diameter(r_geom_b) * 0.05), RGeo::Feature::Geometry)
      b_over_a = T.let(r_geom_b - r_geom_a.buffer(geom_diameter(r_geom_a) * 0.05), RGeo::Feature::Geometry)

      if a_over_b.empty? || b_over_a.empty?
        # One subpart of the other
        [0.0, a_over_b.empty? ? nil : a_over_b, b_over_a.empty? ? nil : b_over_a]
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
          # And fallback, all converted as polygons
          d = (
            T.cast(a_over_b, RGeo::Feature::Polygon).area +
            T.cast(b_over_a, RGeo::Feature::Polygon).area
          ) / union.area / 2
          [d, a_over_b, b_over_a]
        end
      end
    elsif r_geom_a.dimension == 0 && r_geom_b.dimension == 0
      # Point never intersects
      d = log_distance(r_geom_a, r_geom_b, demi_distance)
      if d <= 0.5
        [d * 2, nil, nil]
      end
    else
      # Else, use real distance + bias because no intersection
      d = 0.5 + log_distance(r_geom_a, r_geom_b, demi_distance) / 2
      [d, nil, nil]
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
      geom: T.any(T::Hash[String, T.untyped], RGeo::Feature::Geometry),
      geo_factory: T.untyped,
      projection: T.untyped,
    ).returns(RGeo::Feature::Geometry)
  }
  def self.cache_geom(geom, geo_factory, projection)
    return T.cast(geom, RGeo::Feature::Geometry) if T.unsafe(geom).respond_to?(:geometry_type) # is_a?(RGeo::Feature::Geometry)

    RGeo::Feature.cast(
      RGeo::GeoJSON.decode(geom, geo_factory: geo_factory),
      project: true,
      factory: projection,
    )
  end

  sig {
    params(
      befores: T::Hash[[String, Integer], Validation::OSMChangeProperties],
      afters: T::Hash[[String, Integer], Validation::OSMChangeProperties],
      afters_index: T::Hash[[String, Integer], Validation::OSMChangeProperties],
    ).returns([Conflations, T::Hash[[String, Integer], Validation::OSMChangeProperties], T::Hash[[String, Integer], Validation::OSMChangeProperties]])
  }
  def self.conflate_by_refs(befores, afters, afters_index)
    befores_refs = befores.values.group_by{ |b| refs(b['tags']) }
    befores_refs.delete({})
    befores_refs = befores_refs.select{ |_k, v| v.size == 1 }.transform_values{ |v| T.must(v.first) }
    afters_refs = afters.values.group_by{ |a| refs(a['tags']) }
    afters_refs.delete({})
    afters_refs = afters_refs.select{ |_k, v| v.size == 1 }.transform_values{ |v| T.must(v.first) }

    uniq_befores_refs = befores_refs.keys
    uniq_afters_refs = afters_refs.keys

    conflate = (uniq_befores_refs & uniq_afters_refs).collect{ |ref|
      before_key = [T.must(befores_refs[ref])['objtype'], T.must(befores_refs[ref])['id']]
      befores.delete(before_key)
      afters.delete([T.must(afters_refs[ref])['objtype'], T.must(afters_refs[ref])['id']])

      [
        befores_refs[ref],
        afters_index[before_key],
        afters_refs[ref]
      ]
    }

    [conflate, befores, afters]
  end

  sig {
    params(
      befores: T::Array[Validation::OSMChangeProperties],
      afters: T::Array[Validation::OSMChangeProperties],
      local_srid: Integer,
      demi_distance: Float,
    ).returns(T::Hash[[Validation::OSMChangeProperties, Validation::OSMChangeProperties], [Float, [Float, T.nilable(RGeo::Feature::Geometry), T.nilable(RGeo::Feature::Geometry)], Float]])
  }
  def self.conflate_matrix(befores, afters, local_srid, demi_distance)
    distance_matrix = T.let({}, T::Hash[[Validation::OSMChangeProperties, Validation::OSMChangeProperties], [Float, [Float, T.nilable(RGeo::Feature::Geometry), T.nilable(RGeo::Feature::Geometry)], Float]])
    geo_factory = RGeo::Geos.factory(srid: 4326)
    projection = RGeo::Geos.factory(srid: local_srid)
    befores.each{ |b|
      afters.each{ |a|
        next if b['geom'].nil? && a['geom'].nil?

        t_dist = tags_distance(b['tags'], a['tags'])
        next if t_dist.nil? || t_dist >= 0.5

        b['geom'] = cache_geom(b['geom'], geo_factory, projection)
        a['geom'] = cache_geom(a['geom'], geo_factory, projection)
        g_dist = (
          if b['geom'] == a['geom'] || (b['geom'].dimension == 2 && a['geom'].dimension == 2 && befores.size == 1 && afters.size == 1)
            # Same geom
            # or
            # Geom distance does not matter on 1x1 matrix, fast return
            [0.0, nil, nil]
          else
            geom_distance(b['geom'], a['geom'], demi_distance)
          end
        )

        if !g_dist.nil?
          distance_matrix[[b, a]] = [
            t_dist,
            g_dist,
            (b['objtype'] == a['objtype'] && b['id'] == a['id'] ? 0.0 : 0.000001),
          ]
        end
      }
    }

    distance_matrix
  end

  sig {
    params(
      befores: T::Hash[[String, Integer], Validation::OSMChangeProperties],
      afters: T::Hash[[String, Integer], Validation::OSMChangeProperties],
      distance_matrix: T::Hash[[Validation::OSMChangeProperties, Validation::OSMChangeProperties], [Float, [Float, T.nilable(RGeo::Feature::Geometry), T.nilable(RGeo::Feature::Geometry)], Float]],
      afters_index: T::Hash[[String, Integer], Validation::OSMChangeProperties],
      local_srid: Integer,
      demi_distance: Float,
    ).returns([Conflations, T::Hash[[String, Integer], Validation::OSMChangeProperties], T::Hash[[String, Integer], Validation::OSMChangeProperties]])
  }
  def self.conflate_core(befores, afters, distance_matrix, afters_index, local_srid, demi_distance)
    paired = T.let([], Conflations)
    until distance_matrix.empty?
      key_min, dist = T.must(distance_matrix.to_a.min_by{ |_keys, coefs| coefs[0] + coefs[1][0] + coefs[2] })
      match = [key_min[0], afters_index[[key_min[0]['objtype'], key_min[0]['id']]], key_min[1]]
      match[-1]['geom_distance'] = (
        if match[0]['geom'].intersects?(match[-1]['geom'])
          DistanceHausdorff.distance(match[0]['geom'], match[-1]['geom'])
        else
          match[0]['geom'].distance(match[-1]['geom'])
        end
      )
      paired << match

      befores.delete([key_min[0]['objtype'], key_min[0]['id']])
      afters.delete([key_min[1]['objtype'], key_min[1]['id']])

      distance_matrix = distance_matrix.select{ |k, _v| (k & key_min).empty? }

      # Add the remaining geom parts to the matrix
      remaning_before_geom = dist[1][1]
      remaning_after_geom = dist[1][2]
      remaning_before = T.let(nil, T.nilable(Validation::OSMChangeProperties))
      remaning_after = T.let(nil, T.nilable(Validation::OSMChangeProperties))
      if !T.unsafe(remaning_before_geom).nil?
        remaning_before = key_min[0].dup
        remaning_before['geom'] = remaning_before_geom
        distance_matrix = distance_matrix.merge(conflate_matrix([remaning_before], afters.values, local_srid, demi_distance))
      end
      if !T.unsafe(remaning_after_geom).nil?
        remaning_after = key_min[1].dup
        remaning_after['geom'] = remaning_after_geom
        distance_matrix = distance_matrix.merge(conflate_matrix(befores.values, [remaning_after], local_srid, demi_distance))
      end
      if !remaning_before.nil? && !remaning_after.nil?
        distance_matrix = distance_matrix.merge(conflate_matrix(
          [T.cast(remaning_before, Validation::OSMChangeProperties)],
          [T.cast(remaning_after, Validation::OSMChangeProperties)],
          local_srid, demi_distance
        ))
      end
    end

    [paired, befores, afters]
  end

  sig {
    params(
      befores: T::Enumerable[Validation::OSMChangeProperties],
      afters: T::Enumerable[Validation::OSMChangeProperties],
      local_srid: Integer,
      demi_distance: Float,
    ).returns(Conflations)
  }
  def self.conflate(befores, afters, local_srid, demi_distance)
    afters_index = afters.index_by{ |a| [a['objtype'], a['id']] }
    afters = afters.select{ |a| !a['deleted'] }

    befores = befores.index_by{ |b| [b['objtype'], b['id']] }
    afters = afters.index_by{ |a| [a['objtype'], a['id']] }

    paired_by_refs, befores, afters = conflate_by_refs(befores, afters, afters_index)

    distance_matrix = conflate_matrix(befores.values, afters.values, local_srid, demi_distance)
    paired_by_distance, befores, afters = conflate_core(befores, afters, distance_matrix, afters_index, local_srid, demi_distance)

    T.cast((
      paired_by_refs +
      paired_by_distance +
      befores.values.collect{ |b| [b, afters_index[[b['objtype'], b['id']]], nil] } +
      afters.values.collect{ |a| [nil, nil, a] }
    ), Conflations)
  end
end
