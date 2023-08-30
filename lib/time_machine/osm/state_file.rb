# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module Osm
  class StateFile < T::InexactStruct
    extend T::Sig

    const :sequence_number, Integer
    const :timestamp, String

    sig{
      params(
        path: String
      ).returns(T.nilable(StateFile))
    }
    def self.from_file(path)
      return unless File.exist?(path)

      sequence_number = T.let(nil, T.nilable(Integer))
      timestamp = T.let(nil, T.nilable(String))
      File.readlines(path).each{ |line|
        if line.start_with?('sequenceNumber=')
          sequence_number = line.strip.split('=', 2)[1].to_i
        elsif line.start_with?('timestamp=')
          timestamp = line.strip.split('=', 2)[1]&.gsub('\\:', ':')
        end
      }

      return unless !sequence_number.nil? && !timestamp.nil?

      StateFile.new(
        sequence_number: sequence_number,
        timestamp: timestamp,
      )
    end

    sig{
      params(
        path: String
      ).void
    }
    def save_to(path)
      File.write(path, "timestamp=#{timestamp}
sequenceNumber=#{sequence_number}
")
    end
  end
end
