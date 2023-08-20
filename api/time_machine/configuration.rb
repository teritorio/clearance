# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'yaml'
require './time_machine/validators/validator_factory'
require 'open-uri'

module Configuration
  extend T::Sig

  class MainConfig < T::Struct
    const :title, T::Hash[String, String]
    const :description, T::Hash[String, String]
    const :validators, T::Hash[String, T::Hash[String, T.untyped]]
    const :user_groups, T.nilable(T::Hash[String, T::Hash[String, T.untyped]])
  end

  class UserGroupConfig < T::Struct
    const :title, T::Hash[String, String]
    const :polygon, T.nilable(String)
    const :users, T::Array[String]
  end

  class Config < T::Struct
    const :title, T::Hash[String, String]
    const :description, T::Hash[String, String]
    const :validators, T::Array[Validators::ValidatorBase]
    const :osm_tags_matches, OsmTagsMatches::OsmTagsMatches
    const :user_groups, T::Hash[String, UserGroupConfig]
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
    osm_tags = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])
    user_groups = config.user_groups&.to_h{ |group_id, v|
      j = JSON.parse(T.cast(URI.parse(v['osm_tags']), URI::HTTP).read)
      osm_tags += j.collect{ |rule|
        rule['sources'] = rule['sources'].collect{ |s| [group_id, s] }
        rule
      }

      [group_id, UserGroupConfig.from_hash(v)]
    } || {}

    osm_tags = osm_tags.group_by{ |t| [t['select'], t['interest']] }.transform_values{ |group|
      group0 = T.must(group[0]) # Just to keep sorbet happy
      {
        'select' => group0['select'],
        'interest' => group0['interest'],
        'sources' => group.pluck('sources').flatten(1).group_by(&:last).transform_values{ |j| j.collect(&:first).join(', ') }.collect{ |source, group_ids| "#{group_ids}: #{source}" }
      }
    }.values

    osm_tags_matches = OsmTagsMatches::OsmTagsMatches.new(osm_tags.collect{ |value|
      OsmTagsMatches::OsmTagsMatch.new(
        value['select'],
        selector_extra: value['interest'],
        sources: value['sources'],
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
      user_groups: user_groups
    )
  end
end
