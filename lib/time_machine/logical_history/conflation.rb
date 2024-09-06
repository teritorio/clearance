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
require './lib/time_machine/logical_history/refs'
require './lib/time_machine/logical_history/tags'
require './lib/time_machine/logical_history/geom'


module LogicalHistory
  module Conflation
    extend T::Sig

    class Conflation < T::InexactStruct
      const :before, Validation::OSMChangeProperties
      const :before_at_now, Validation::OSMChangeProperties
      const :after, Validation::OSMChangeProperties

      extend T::Sig
      sig { returns(T::Array[Validation::OSMChangeProperties]) }
      def to_a
        [before, before_at_now, after]
      end
    end

    Conflations = T.type_alias { T::Array[Conflation] }

    class ConflationNilable < T::InexactStruct
      const :before, T.nilable(Validation::OSMChangeProperties)
      const :before_at_now, T.nilable(Validation::OSMChangeProperties)
      const :after, T.nilable(Validation::OSMChangeProperties)

      extend T::Sig
      sig { returns(T::Array[T.nilable(Validation::OSMChangeProperties)]) }
      def to_a
        [before, before_at_now, after]
      end
    end

    ConflationsNilable = T.type_alias { T::Array[ConflationNilable] }

    sig {
      params(
        geom: T.any(T::Hash[String, T.untyped], RGeo::Feature::Geometry),
        geo_factory: T.untyped,
        projection: T.untyped,
      ).returns(T.nilable(RGeo::Feature::Geometry))
    }
    def self.cache_geom(geom, geo_factory, projection)
      return T.cast(geom, RGeo::Feature::Geometry) if T.unsafe(geom).respond_to?(:geometry_type) # is_a?(RGeo::Feature::Geometry)

      begin
        RGeo::Feature.cast(
          RGeo::GeoJSON.decode(geom, geo_factory: geo_factory),
          project: true,
          factory: projection,
        )
      rescue RGeo::Error::InvalidGeometry
        nil
      end
    end

    sig {
      params(
        befores: T::Hash[[String, Integer], Validation::OSMChangeProperties],
        afters: T::Hash[[String, Integer], Validation::OSMChangeProperties],
        afters_index: T::Hash[[String, Integer], Validation::OSMChangeProperties],
      ).returns([Conflations, T::Hash[[String, Integer], Validation::OSMChangeProperties], T::Hash[[String, Integer], Validation::OSMChangeProperties]])
    }
    def self.conflate_by_refs(befores, afters, afters_index)
      befores_refs = befores.values.group_by{ |b| LogicalHistory::Refs.refs(b['tags']) }
      befores_refs.delete({})
      befores_refs = befores_refs.select{ |_k, v| v.size == 1 }.transform_values{ |v| T.must(v.first) }
      afters_refs = afters.values.group_by{ |a| LogicalHistory::Refs.refs(a['tags']) }
      afters_refs.delete({})
      afters_refs = afters_refs.select{ |_k, v| v.size == 1 }.transform_values{ |v| T.must(v.first) }

      uniq_befores_refs = befores_refs.keys
      uniq_afters_refs = afters_refs.keys

      conflate = (uniq_befores_refs & uniq_afters_refs).collect{ |ref|
        before_key = [T.must(befores_refs[ref])['objtype'], T.must(befores_refs[ref])['id']]
        befores.delete(before_key)
        afters.delete([T.must(afters_refs[ref])['objtype'], T.must(afters_refs[ref])['id']])

        Conflation.new(
          before: T.must(befores_refs[ref]),
          before_at_now: T.must(afters_index[before_key]),
          after: T.must(afters_refs[ref]),
        )
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
          next if b['geom'].nil? || a['geom'].nil?

          t_dist = LogicalHistory::Tags.tags_distance(b['tags'], a['tags'])
          next if t_dist.nil?

          b['geom'] = cache_geom(b['geom'], geo_factory, projection)
          a['geom'] = cache_geom(a['geom'], geo_factory, projection)
          next if b['geom'].nil? || a['geom'].nil?

          g_dist = (
            if b['geom'] == a['geom'] || (b['geom'].dimension == 2 && a['geom'].dimension == 2 && befores.size == 1 && afters.size == 1)
              # Same geom
              # or
              # Geom distance does not matter on 1x1 matrix, fast return
              [0.0, nil, nil]
            else
              LogicalHistory::Geom.geom_distance(b['geom'], a['geom'], demi_distance)
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
        key_min: [Validation::OSMChangeProperties, Validation::OSMChangeProperties],
        befores: T::Hash[[String, Integer], Validation::OSMChangeProperties],
        afters: T::Hash[[String, Integer], Validation::OSMChangeProperties],
        dist_geom: [Float, T.nilable(RGeo::Feature::Geometry), T.nilable(RGeo::Feature::Geometry)],
      ).returns(T::Array[[
        T::Array[Validation::OSMChangeProperties],
        T::Array[Validation::OSMChangeProperties]
      ]])
    }
    def self.remaining_parts(key_min, befores, afters, dist_geom)
      parts = T.let([], T::Array[[
        T::Array[Validation::OSMChangeProperties],
        T::Array[Validation::OSMChangeProperties]
      ]])

      remaning_before_geom = dist_geom[1]
      remaning_after_geom = dist_geom[2]
      remaning_before = T.let(nil, T.nilable(Validation::OSMChangeProperties))
      remaning_after = T.let(nil, T.nilable(Validation::OSMChangeProperties))
      if !T.unsafe(remaning_before_geom).nil?
        remaning_before = key_min[0].dup
        remaning_before['geom'] = remaning_before_geom
        parts << [[remaning_before], afters.values]
      end
      if !T.unsafe(remaning_after_geom).nil?
        remaning_after = key_min[1].dup
        remaning_after['geom'] = remaning_after_geom
        parts << [befores.values, [remaning_after]]
      end
      if !remaning_before.nil? && !remaning_after.nil?
        parts << [
          [T.cast(remaning_before, Validation::OSMChangeProperties)],
          [T.cast(remaning_after, Validation::OSMChangeProperties)]
        ]
      end

      parts
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
      until distance_matrix.empty? || befores.empty? || afters.empty?
        key_min, dist = T.must(distance_matrix.to_a.min_by{ |_keys, coefs| coefs[0] + coefs[1][0] + coefs[2] })
        match = Conflation.new(
          before: key_min[0],
          before_at_now: T.must(afters_index[[key_min[0]['objtype'], key_min[0]['id']]]),
          after: key_min[1]
        )
        match.after['geom_distance'] = match.before['geom'].distance(match.after['geom'])
        match.after['geom_distance'] = nil if match.after['geom_distance'] == 0
        paired << match

        befores.delete([key_min[0]['objtype'], key_min[0]['id']])
        afters.delete([key_min[1]['objtype'], key_min[1]['id']])

        distance_matrix = distance_matrix.select{ |k, _v| (k & key_min).empty? }

        # Add the remaining geom parts to the matrix
        new_befores = T.let([], T::Array[Validation::OSMChangeProperties])
        new_afters = T.let([], T::Array[Validation::OSMChangeProperties])
        remaining_parts(key_min, befores, afters, dist[1]).each{ |parts|
          new_befores += parts[0]
          new_afters += parts[1]
        }
        distance_matrix = distance_matrix.merge(
          conflate_matrix(new_befores, new_afters, local_srid, demi_distance),
          conflate_matrix(new_befores, afters.values, local_srid, demi_distance),
          conflate_matrix(befores.values, new_afters, local_srid, demi_distance),
        )
      end

      [paired, befores, afters]
    end

    sig {
      params(
        befores: T::Enumerable[Validation::OSMChangeProperties],
        afters: T::Enumerable[Validation::OSMChangeProperties],
        local_srid: Integer,
        demi_distance: Float,
      ).returns(ConflationsNilable)
    }
    def self.conflate(befores, afters, local_srid, demi_distance)
      afters_index = afters.index_by{ |a| [a['objtype'], a['id']] }
      afters = afters.select{ |a| !a['deleted'] }

      befores = befores.index_by{ |b| [b['objtype'], b['id']] }
      afters = afters.index_by{ |a| [a['objtype'], a['id']] }

      paired_by_refs, befores, afters = conflate_by_refs(befores, afters, afters_index)

      distance_matrix = conflate_matrix(befores.values, afters.values, local_srid, demi_distance)
      paired_by_distance, befores, afters = conflate_core(befores, afters, distance_matrix, afters_index, local_srid, demi_distance)

      T.cast(paired_by_refs, T::Array[ConflationNilable]) +
        T.cast(paired_by_distance, T::Array[ConflationNilable]) +
        befores.values.collect{ |b| ConflationNilable.new(before: b, before_at_now: afters_index[[b['objtype'], b['id']]]) } +
        afters.values.collect{ |a| ConflationNilable.new(after: a) }
    end
  end
end
