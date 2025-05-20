# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'pg'

module Db
  extend T::Sig

  class DbConnRead
    extend T::Sig

    sig {
      params(
        project: String,
        block: T.proc.params(conn: PG::Connection).void,
      ).void
    }
    def self.conn(project, &block)
      conn0 = PG::Connection.new('postgresql://postgres@postgres:5432/postgres')
      conn0.type_map_for_results = PG::BasicTypeMapForResults.new(conn0)

      # Avoid SQL injection
      raise 'Invalid project name' if !(project =~ /[-A-Za-z0-9_]+/)

      conn0.exec("SET search_path = #{project},public")
      block.call(conn0)
    end
  end

  class DbConnWrite < DbConnRead
    extend T::Sig

    sig {
      params(
        project: String,
        block: T.proc.params(conn: PG::Connection).void,
      ).void
    }
    def self.conn(project, &block)
      super { |conn0|
        conn0.transaction(&block)
      }
    end
  end
end
