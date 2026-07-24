# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module Db
  extend T::Sig

  sig {
    params(
      conn: PG::Connection,
      dump: String,
    ).void
  }
  def self.import_changes(conn, dump)
    conn.exec(File.read('/sql/00_import_changes.sql').gsub(':pgcopy', dump))
  end
end
