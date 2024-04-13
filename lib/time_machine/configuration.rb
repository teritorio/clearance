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
  end

  class UserGroupConfig < T::Struct
    extend T::Sig

    const :title, MultilingualString
    const :polygon, T.nilable(String)
    const :users, T::Array[String]

    sig {
      returns(T::Hash[String, T.untyped])
    }
    def polygon_geojson
      cache = WebCache.new(dir: '/cache/polygons/', life: '1d')
      response = cache.get(polygon)
      raise [polygon, response].inspect if !response.success?

      JSON.parse(response.content)
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
  end

  sig {
    params(
      config: MainConfig
    ).returns([
      T::Hash[String, UserGroupConfig],
      Osm::TagsMatches
    ])
  }
  def self.load_user_groups(config)
    osm_tags = T.let([], T::Array[{ 'select' => T::Array[String], 'interest' => T.nilable(T::Hash[String, T.untyped]), 'sources' => T::Array[String] }])
    user_groups = config.user_groups.nil? ? {} : config.user_groups&.to_h{ |group_id, v|
      j = JSON.parse(T.cast(URI.parse(v['osm_tags']), URI::HTTP).read)
      osm_tags += j.collect{ |rule|
        rule['group_id'] = group_id
        rule
      }

      [group_id, UserGroupConfig.from_hash(v)]
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
      path: String
    ).returns(Config)
  }
  def self.load(path)
    config_yaml = YAML.unsafe_load_file(path)
    config = MainConfig.from_hash(config_yaml)

    user_groups, osm_tags_matches = load_user_groups(config)
    validators = Validation.validators_factory(config.validators, osm_tags_matches)

    Config.new(
      title: config.title,
      description: config.description,
      validators: validators,
      osm_tags_matches: osm_tags_matches,
      main_contacts: config.main_contacts,
      user_groups: user_groups,
      project_tags: config.project_tags,
    )
  end
end
