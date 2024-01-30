# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/db/overpasslike'


class TestOverpass < Test::Unit::TestCase
  extend T::Sig

  sig { void }
  def test_parse
    query = <<~OVERPASS
      [out:json][timeout:25];
      area(id:3600000001)->.a;
      (
        nwr[a=e]["i"~.*](area.a);
        nwr[foo=bar](area.a);
      );
      out center meta;
    OVERPASS
    assert_equal([
      ['[a=e]["i"~.*]', [1]],
      ['[foo=bar]', [1]],
    ], Db::Overpass.parse(query))
  end
end
