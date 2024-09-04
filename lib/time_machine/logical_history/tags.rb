# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'


module LogicalHistory
  module Tags
    extend T::Sig

    # OSM main tags from https://github.com/osm-fr/osmose-backend/blob/dev/plugins/TagFix_MultipleTag.py
    # Exluding "building[:*]"
    MAIN_TAGS = T.let(Set.new(['aerialway', 'aeroway', 'amenity', 'barrier', 'boundary', 'craft', 'disc_golf', 'entrance', 'emergency', 'geological', 'highway', 'historic', 'landuse', 'leisure', 'man_made', 'military', 'natural', 'office', 'place', 'power', 'public_transport', 'railway', 'route', 'shop', 'sport', 'tourism', 'waterway', 'mountain_pass', 'traffic_sign', 'golf', 'piste:type', 'junction', 'healthcare', 'health_facility:type', 'indoor', 'club', 'seamark:type', 'attraction', 'information', 'advertising', 'ford', 'cemetery', 'area:highway', 'checkpoint', 'telecom', 'airmark']), T::Set[String])

    # nil means any value in in the class
    MAIN_TAGS_CLASS_OF_VALUES = T.let({
      'barrier' => nil,
      'boundary' => nil,

      'craft' => nil,
      'shop' => nil,
      'office' => nil,
      'sport' => nil,

      'highway' => %w[motorway trunk primary secondary tertiary unclassified residential motorway_link trunk_link primary_link secondary_link tertiary_link living_street service pedestrian track bus_guideway escape raceway road busway footway bridleway steps corridor path via_ferrata],
      'railway' => %w[abandoned construction disused funicular light_rail miniature monorail narrow_gauge preserved rail subway tram],
      'waterway' => %w[river riverbank stream tidal_channel flowline canal pressurised drain ditch],
      'landuse' => nil,

      'entrance' => nil,
      'place' => nil,
      'junction' => nil,
      'ford' => nil,
    }, T::Hash[String, T.nilable(T::Array[String])])

    sig {
      params(
        tags_a: T::Hash[String, String],
        tags_b: T::Hash[String, String],
      ).returns(T.nilable(Float))
    }
    def self.key_val_main_distance(tags_a, tags_b)
      return nil if tags_a.empty? && tags_b.empty?
      return 1.0 if tags_a.empty? || tags_b.empty?

      keys = (tags_a.keys + tags_b.keys).uniq
      keys.sum(0.0) { |key|
        if tags_a[key] == tags_b[key]
          0.0
        elsif tags_a.key?(key) && tags_b.key?(key) && MAIN_TAGS_CLASS_OF_VALUES.key?(key) && MAIN_TAGS_CLASS_OF_VALUES[key].nil? || (MAIN_TAGS_CLASS_OF_VALUES[key]&.include?(tags_a[key]) && MAIN_TAGS_CLASS_OF_VALUES[key]&.include?(tags_b[key]))
          # Same key with values in the same range class
          0.5
        else
          1.0
        end
      } / keys.size
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
      return if d_main.nil? || d_main >= 1.0

      # Other tags
      (d_main + key_val_fuzzy_distance(T.must(a)[1] || {}, T.must(b)[1] || {})) / 2
    end
  end
end
