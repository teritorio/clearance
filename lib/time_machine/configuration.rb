# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'yaml'
require './lib/time_machine/validators/validator_factory'
require 'open-uri'

module Configuration
  extend T::Sig

  class MainConfig < T::Struct
    const :title, T::Hash[String, String]
    const :description, T::Hash[String, String]
    const :validators, T::Hash[String, T::Hash[String, T.untyped]]
    const :main_contacts, T::Array[String]
    const :user_groups, T.nilable(T::Hash[String, T::Hash[String, T.untyped]])
    const :project_tags, T::Array[String]
  end

  class UserGroupConfig < T::Struct
    extend T::Sig

    const :title, T::Hash[String, String]
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
    const :title, T::Hash[String, String]
    const :description, T::Hash[String, String]
    const :validators, T::Array[Validators::ValidatorBase]
    const :osm_tags_matches, OsmTagsMatches::OsmTagsMatches
    const :main_contacts, T::Array[String]
    const :user_groups, T::Hash[String, UserGroupConfig]
    const :project_tags, T::Array[String]
  end

  sig {
    params(
      config: MainConfig
    ).returns([
      T::Hash[String, UserGroupConfig],
      OsmTagsMatches::OsmTagsMatches
    ])
  }
  def self.load_user_groups(config)
    osm_tags = T.let([], T::Array[T::Hash[String, T::Hash[Symbol, T.untyped]]])
    user_groups = config.user_groups&.to_h{ |group_id, v|
      j = JSON.parse(T.cast(URI.parse(v['osm_tags']), URI::HTTP).read)
      osm_tags += j.collect{ |rule|
        rule['group_id'] = group_id
        rule
      }

      [group_id, UserGroupConfig.from_hash(v)]
    } || {}

    osm_tags = osm_tags.group_by{ |t| [t['select'], t['interest']] }.transform_values{ |group|
      group0 = T.must(group[0]) # Just to keep sorbet happy
      {
        'select' => group0['select'],
        'interest' => group0['interest'],
        'sources' => group.pluck('sources').flatten.uniq,
        'group_ids' => group.pluck('group_id').flatten,
      }
    }.values

    osm_tags_matches = OsmTagsMatches::OsmTagsMatches.new(osm_tags.collect{ |value|
      OsmTagsMatches::OsmTagsMatch.new(
        value['select'],
        selector_extra: value['interest'],
        sources: value['sources'],
        user_groups: value['group_ids'],
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
    validators = Validators::ValidatorFactory.validators_factory(config.validators, osm_tags_matches)

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
