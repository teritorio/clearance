# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/types'
require './lib/time_machine/validators/validator_link'

require 'webcache'
require 'parquet'
require 'stringio'

module Validators
  extend T::Sig

  class UserKarmaMap < ValidatorLinkDual
    extend T::Sig

    class Settings < ValidatorBase::Settings
      const :description, String, override: true, default: 'Auto Black list and White list users using KarmaMap API.'
      const :karmamap_base_url, String, default: 'https://karmamap.teritorio.xyz'
      const :black_list_ranking, T.nilable(Float), default: 1.0
      const :white_list_ranking, T.nilable(Float), default: 95.0
    end

    extend T::Generic

    SettingsType = type_member{ { upper: Settings } }

    sig {
      params(
        settings: SettingsType,
        actions: T::Hash[String, String],
      ).void
    }
    def initialize(settings:, actions:)
      super
      @ranks = T.let(nil, T.nilable(T::Hash[Integer, Float]))
    end

    sig {
      override.params(
        _before: T.nilable(Validation::OSMChangeProperties),
        after: T.nilable(Validation::OSMChangeProperties),
        diff: Validation::DiffActions,
        _conflation_reason: OSMLogicalHistory::Conflation::ConflationReason,
      ).void
    }
    def apply_link(_before, after, diff, _conflation_reason)
      uid = after&.uid
      return if uid.nil?

      @ranks ||= rankings
      rank = T.let(@ranks[uid] || 0.0, Float)

      if !@settings.black_list_ranking.nil? && rank < T.must(@settings.black_list_ranking)
        attribs_username = diff.attribs['username'] ||= []
        assign_action_reject(attribs_username)
      elsif !@settings.white_list_ranking.nil? && rank > T.must(@settings.white_list_ranking)
        attribs_username = diff.attribs['username'] ||= []
        assign_action_accept(attribs_username)
      end
    end

    private

    sig {
      returns(T::Hash[Integer, Float])
    }
    def rankings
      cache = WebCache.new(dir: '/cache/karmamap/', life: '1h')
      url = "#{@settings.karmamap_base_url}/data/user_ranking.parquet"
      response = cache.get(url)
      raise [response.error, url].join(' ') if !response.success?

      table = {}
      begin
        Parquet.each_column(StringIO.new(response.content), columns: %w[uid ranking]) { |batch|
          batch['uid'].zip(batch['ranking']).each { |uid, value|
            table[uid.to_i] = value.to_f
          }
        }
      rescue RuntimeError
        cache.clear(url)
        raise
      end
      table
    end
  end
end
