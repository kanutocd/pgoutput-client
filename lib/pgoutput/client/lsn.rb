# frozen_string_literal: true

module Pgoutput
  module Client
    # PostgreSQL Log Sequence Number conversion helpers.
    #
    # PostgreSQL represents LSNs as two hexadecimal 32-bit halves separated by a
    # slash, such as `0/16B6C50`. The replication protocol transmits the same WAL
    # position as an unsigned 64-bit integer. This module converts between those
    # two representations.
    #
    # @example Parse a textual LSN
    #   Pgoutput::Client::LSN.parse("0/10")
    #   # => 16
    #
    # @example Format an integer WAL position
    #   Pgoutput::Client::LSN.format(16)
    #   # => "0/10"
    #
    # @api public
    module LSN
      module_function

      # Parse a PostgreSQL LSN string into an integer WAL position.
      #
      # @param value [#to_s] LSN string in `HEX/HEX` form
      # @return [Integer] unsigned 64-bit WAL position
      # @raise [ArgumentError] if the value is not a valid LSN string
      def parse(value)
        high, low = String(value).split("/", 2)
        raise ArgumentError, "invalid LSN: #{value.inspect}" if high.nil? || low.nil?

        (Integer(high, 16) << 32) + Integer(low, 16)
      rescue ArgumentError
        raise ArgumentError, "invalid LSN: #{value.inspect}"
      end

      # Format an integer WAL position as a PostgreSQL LSN string.
      #
      # @param value [#to_int, #to_s] non-negative integer WAL position
      # @return [String] LSN string in uppercase hexadecimal `HEX/HEX` form
      # @raise [ArgumentError] if the value is negative or cannot be coerced to
      #   an integer
      def format(value)
        integer = Integer(value)
        raise ArgumentError, "LSN must be non-negative" if integer.negative?

        high = integer >> 32
        low = integer & 0xFFFF_FFFF
        "#{high.to_s(16).upcase}/#{low.to_s(16).upcase}"
      end
    end
  end
end
