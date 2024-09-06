# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require './lib/time_machine/validation/changes_db'
require './lib/time_machine/validation/types'


module Validation
  extend T::Sig

  class DiffActions < T::Struct
    extend T::Sig

    const :attribs, Validation::HashActions
    const :tags, Validation::HashActions

    sig {
      returns(T::Boolean)
    }
    def fully_accepted?
      (attribs.empty? || attribs.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } }) &&
        (tags.empty? || tags.values.all?{ |actions| !actions.empty? && actions.all?{ |action| action.action == 'accept' } })
    end

    sig {
      returns(T::Boolean)
    }
    def partialy_rejected?
      attribs.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } } ||
        tags.values.any?{ |actions| actions.any?{ |action| action.action == 'reject' } }
    end
  end

  sig {
    params(
      before: T.nilable(OSMChangeProperties),
      after: T.nilable(OSMChangeProperties),
    ).returns(DiffActions)
  }
  def self.diff_osm_object(before, after)
    diff_attribs = T.let({}, HashActions)
    diff_tags = T.let({}, HashActions)

    # Unchecked attribs
    # - version
    # - changeset
    # - uid
    # - username
    # - nodes
    # - lat
    # - lon
    %i[deleted members geom_distance].each { |attrib|
      diff_attribs[attrib.to_s] = [] if before&.send(attrib) != after&.send(attrib)
    }

    ((before&.tags&.keys || []) + (after&.tags&.keys || [])).uniq.each{ |tag|
      diff_tags[tag] = [] if (before&.tags || tag) != (after&.tags || tag)
    }

    DiffActions.new(attribs: diff_attribs, tags: diff_tags)
  end
end
