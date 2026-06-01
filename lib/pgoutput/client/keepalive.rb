# frozen_string_literal: true

module Pgoutput
  module Client
    KeepaliveData = Data.define(:wal_end, :server_clock, :reply_requested)

    # Immutable primary keepalive replication message.
    #
    # PostgreSQL sends keepalive CopyData payloads while a replication stream is
    # active. The payload layout is:
    #
    # ```text
    # Byte 0      : message tag `k`
    # Bytes 1-8   : current server WAL end, unsigned 64-bit big-endian
    # Bytes 9-16  : server clock, PostgreSQL timestamp format
    # Byte 17     : reply-requested flag, 1 for immediate feedback
    # ```
    #
    # The stream layer uses this message to advance its known WAL position and to
    # decide whether to send standby status feedback immediately.
    #
    # @attr_reader wal_end [Integer] latest server WAL position
    # @attr_reader server_clock [Integer] PostgreSQL server timestamp in
    #   microseconds since 2000-01-01 UTC
    # @attr_reader reply_requested [Boolean] whether PostgreSQL requested
    #   immediate feedback
    class Keepalive < KeepaliveData
      # Parse a keepalive CopyData payload.
      #
      # @param bytes [String] raw CopyData payload beginning with `k`
      # @return [Keepalive] immutable parsed keepalive message
      # @raise [ProtocolError] if the payload is empty, has the wrong message
      #   tag, or is too short to contain the required fields
      def self.parse(bytes)
        binary = bytes.b
        raise ProtocolError, "empty CopyData payload" if binary.empty?
        raise ProtocolError, "expected keepalive message" unless binary.getbyte(0) == "k".ord
        raise ProtocolError, "truncated keepalive message" if binary.bytesize < 18

        wal_end = unpack_u64(binary, 1)
        server_clock = unpack_u64(binary, 9)
        reply_requested = binary.getbyte(17) == 1

        Ractor.make_shareable(new(wal_end, server_clock, reply_requested))
      end

      # Latest server WAL position formatted as a PostgreSQL LSN string.
      #
      # @return [String]
      def wal_end_lsn = LSN.format(wal_end)

      # @param binary [String]
      # @param offset [Integer]
      # @return [Integer]
      def self.unpack_u64(binary, offset)
        value = binary.byteslice(offset, 8)&.unpack1("Q>")
        raise ProtocolError, "failed to unpack uint64" unless value.is_a?(Integer)

        value
      end
      private_class_method :unpack_u64
    end
  end
end
