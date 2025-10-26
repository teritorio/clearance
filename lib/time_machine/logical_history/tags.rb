# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'levenshtein'


module LogicalHistory
  module Tags
    extend T::Sig

    DistanceMeusure = T.type_alias {
      [
        Float,
        T.nilable(T::Hash[String, String]),
        T.nilable(T::Hash[String, String]),
        String, # Reason
      ]
    }

    # OSM main tags from https://github.com/osm-fr/osmose-backend/blob/dev/plugins/TagFix_MultipleTag.py
    # Exluding "building[:*]"
    MAIN_TAGS = T.let(Set.new(['aerialway', 'aeroway', 'amenity', 'building', 'barrier', 'boundary', 'craft', 'disc_golf', 'entrance', 'emergency', 'geological', 'highway', 'historic', 'landuse', 'leisure', 'man_made', 'military', 'natural', 'office', 'place', 'power', 'public_transport', 'railway', 'route', 'shop', 'sport', 'tourism', 'waterway', 'mountain_pass', 'traffic_sign', 'golf', 'piste:type', 'junction', 'healthcare', 'health_facility:type', 'indoor', 'club', 'seamark:type', 'attraction', 'information', 'advertising', 'ford', 'cemetery', 'area:highway', 'checkpoint', 'telecom', 'airmark']), T::Set[String])

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
      'natural' => nil,
      'building' => nil,

      'entrance' => nil,
      'place' => nil,
      'junction' => nil,
      'ford' => nil,
    }, T::Hash[String, T.nilable(T::Array[String])])

    sig {
      params(
        key: String,
        value_a: T.nilable(String),
        value_b: T.nilable(String),
      ).returns(T::Boolean)
    }
    def self.key_of_same_class(key, value_a, value_b)
      !value_a.nil? && !value_b.nil? &&
        MAIN_TAGS_CLASS_OF_VALUES.key?(key) && (
        MAIN_TAGS_CLASS_OF_VALUES[key].nil? ||
        (
          T.must(MAIN_TAGS_CLASS_OF_VALUES[key]).include?(value_a) &&
          T.must(MAIN_TAGS_CLASS_OF_VALUES[key]).include?(value_b)
        )
      )
    end

    sig {
      params(
        tags_a: T::Hash[String, String],
        tags_b: T::Hash[String, String],
      ).returns(T.nilable([Float, T::Array[String]]))
    }
    def self.key_val_main_distance(tags_a, tags_b)
      return nil if tags_a.empty? && tags_b.empty?
      return [1.0, []] if tags_a.empty? || tags_b.empty?

      keys = (tags_a.keys + tags_b.keys).uniq
      dt = keys.collect { |key|
        if tags_a[key] == tags_b[key]
          [0.0, "#{key}=#{tags_a[key]}"]
        elsif key_of_same_class(key, tags_a[key], tags_b[key])
          # Same key with values in the same range class
          [0.5, "#{key}=#{tags_a[key]}/#{tags_b[key]}"]
        else
          [1.0, nil]
        end
      }
      [dt.sum(0.0, &:first) / keys.size, dt.collect(&:last).compact]
    end

    # TODO: et les mulit valeurs ?

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

    sig { params(tags: T::Hash[String, String]).returns([T::Hash[String, String], T::Hash[String, String]]) }
    def self.main_second_tags(tags)
      p = tags.partition{ |k, _v| MAIN_TAGS.include?(k) }.collect(&:to_h)
      [p[0] || {}, p[1] || {}]
    end

    sig {
      params(
        tags_a: T::Hash[String, String],
        tags_b: T::Hash[String, String],
      ).returns(T.nilable(DistanceMeusure))
    }
    def self.tags_distance(tags_a, tags_b)
      main_tags_a, other_tags_a = main_second_tags(tags_a)
      main_tags_b, other_tags_b = main_second_tags(tags_b)

      # Main tags
      d_main, reason_main = key_val_main_distance(main_tags_a, main_tags_b)
      return if d_main.nil? || d_main >= 1.0

      # Symmetrical main tags difference
      remaining_tags_a = main_tags_a.reject{ |k, v| main_tags_b[k] == v || key_of_same_class(k, v, main_tags_b[k]) }.to_h
      remaining_tags_b = main_tags_b.reject{ |k, v| main_tags_a[k] == v || key_of_same_class(k, v, main_tags_a[k]) }.to_h

      # Other tags
      d = (d_main + key_val_fuzzy_distance(other_tags_a, other_tags_b)) / 2

      remaining_tags_a = remaining_tags_a.merge(other_tags_a.reject{ |k, v| other_tags_b[k] == v }.to_h) if !remaining_tags_a.empty?
      remaining_tags_b = remaining_tags_b.merge(other_tags_b.reject{ |k, v| other_tags_a[k] == v }.to_h) if !remaining_tags_b.empty?

      # TODO: Some tags are side tags of main tags, and we could move on one side along the main tag.

      reason = (reason_main || []).sort.join(', ')
      [d, remaining_tags_a.presence, remaining_tags_b.presence, "matched tags: #{reason}"]
    end
  end
end
