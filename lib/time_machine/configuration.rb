# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'yaml'
require './lib/time_machine/validation/validator_factory'
require 'open-uri'

module Configuration
  extend T::Sig

  MultilingualString = T.type_alias { T::Hash[String, String] }

  class MainConfig < T::Struct
    const :title, MultilingualString
    const :description, MultilingualString
    const :validators, T::Hash[String, T::Hash[String, T.untyped]]
    const :main_contacts, T::Array[String]
    const :user_groups, T.nilable(T::Hash[String, { 'title' => String, 'polygon' => String, 'osm_tags' => String, 'users' => T::Array[String] }])
    const :project_tags, T::Array[String]
    const :local_srid, Integer
    const :locha_cluster_distance, Integer
  end

  class UserGroupConfig < T::Struct
    extend T::Sig

    const :path, String, default: './'
    const :title, MultilingualString
    const :polygon, T.nilable(String)
    const :users, T::Array[String]

    sig {
      returns(T.nilable(T::Hash[String, T.untyped]))
    }
    def polygon_geojson
      return nil if polygon.nil?

      content = (
        if T.must(polygon).starts_with?('http')
          cache = WebCache.new(dir: '/cache/polygons/', life: '1d')
          response = cache.get(polygon)
          raise [polygon, response].inspect if !response.success?

          response.content
        else
          File.read(File.expand_path(polygon, path))
        end
      )

      JSON.parse(content)
    end
  end

  class Config < T::Struct
    const :title, MultilingualString, default: {}
    const :description, MultilingualString, default: {}
    const :validators, T::Array[Validators::ValidatorBase], default: []
    const :osm_tags_matches, Osm::TagsMatches, default: Osm::TagsMatches.new([])
    const :main_contacts, T::Array[String], default: []
    const :user_groups, T::Hash[String, UserGroupConfig], default: {}
    const :project_tags, T::Array[String], default: []
    const :local_srid, Integer
    const :locha_cluster_distance, Integer
  end

  sig {
    params(
      path: String,
      config: MainConfig
    ).returns([
      T::Hash[String, UserGroupConfig],
      Osm::TagsMatches
    ])
  }
  def self.load_user_groups(path, config)
    cache = WebCache.new(dir: '/cache/osm_tags/', life: '1h')
    osm_tags = T.let([], T::Array[{ 'select' => T::Array[String], 'interest' => T.nilable(T::Hash[String, T.untyped]), 'sources' => T::Array[String] }])
    # .to_h.collect.to_h => Mak happy Rubocop and Sorbet at the same time
    user_groups = config.user_groups.to_h.collect.to_h{ |group_id, v|
      content = (
        if v['osm_tags'].starts_with?('http')
          response = cache.get(T.cast(URI.parse(v['osm_tags']), URI::HTTP))
          raise [v['osm_tags'], response].inspect if !response.success?

          response.content
        else
          File.read(File.expand_path(v['osm_tags'], path))
        end
      )

      j = JSON.parse(content)
      osm_tags += j.collect{ |rule|
        rule['group_id'] = group_id
        rule
      }

      [group_id, UserGroupConfig.from_hash(v.merge('path' => path))]
    }

    osm_tags_matches = Osm::TagsMatches.new(osm_tags.group_by{ |t| [t['select'], t['interest']] }.values.collect{ |group|
      group0 = T.must(group[0]) # Just to keep sorbet happy
      Osm::TagsMatch.new(
        group0['select'],
        selector_extra: group0['interest'],
        sources: group.pluck('sources').flatten.uniq,
        user_groups: group.pluck('group_id').flatten,
        name: group0['name'],
        icon: group0['icon'],
      )
    })

    [user_groups, osm_tags_matches]
  end

  sig {
    params(
      content: String,
      path: String,
    ).returns(Config)
  }
  def self.parse(content, path)
    config_yaml = YAML.unsafe_load(content)
    config = MainConfig.from_hash(config_yaml)

    user_groups, osm_tags_matches = load_user_groups(path, config)
    validators = Validation.validators_factory(config.validators, osm_tags_matches)

    Config.new(
      title: config.title,
      description: config.description,
      validators: validators,
      osm_tags_matches: osm_tags_matches,
      main_contacts: config.main_contacts,
      user_groups: user_groups,
      project_tags: config.project_tags,
      local_srid: config.local_srid,
      locha_cluster_distance: config.locha_cluster_distance,
    )
  end

  sig {
    params(
      config_file: String
    ).returns(Config)
  }
  def self.load(config_file)
    path = File.dirname(config_file)
    content = File.read(config_file)
    parse(content, path)
  end
end
