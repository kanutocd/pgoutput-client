# frozen_string_literal: true

module Pgoutput
  module Client
    FeedbackData = Data.define(:received_lsn, :flushed_lsn, :applied_lsn, :client_clock, :reply_requested)

    # Standby status feedback message builder.
    #
    # Logical replication clients periodically send standby status updates to
    # tell PostgreSQL which WAL location has been received, flushed, and applied.
    # `Feedback` models that update and can serialize itself into the CopyData
    # payload expected by the replication protocol.
    #
    # @attr_reader received_lsn [Integer] latest WAL location received by the client
    # @attr_reader flushed_lsn [Integer] latest WAL location flushed by the client
    # @attr_reader applied_lsn [Integer] latest WAL location applied by the client
    # @attr_reader client_clock [Integer] PostgreSQL timestamp in microseconds since 2000-01-01 UTC
    # @attr_reader reply_requested [Boolean] whether this feedback is responding to an immediate-reply request
    class Feedback < FeedbackData
      # Build feedback using the current wall-clock time.
      #
      # By default, flushed and applied LSNs follow the received LSN. Callers can
      # pass lower values if they need to distinguish receipt from durable flush
      # or application progress.
      #
      # @param received_lsn [Integer] latest WAL location received by the client
      # @param flushed_lsn [Integer] latest WAL location flushed by the client
      # @param applied_lsn [Integer] latest WAL location applied by the client
      # @param reply_requested [Boolean] whether this is an immediate reply
      # @return [Feedback] immutable feedback value
      def self.now(received_lsn:, flushed_lsn: received_lsn, applied_lsn: flushed_lsn, reply_requested: false)
        new(received_lsn, flushed_lsn, applied_lsn, current_pg_time, reply_requested)
      end

      # Build a protocol CopyData payload for standby status update.
      #
      # The payload begins with the standby status update tag `r`, followed by
      # three unsigned 64-bit LSN fields, the PostgreSQL timestamp, and a
      # one-byte reply-requested flag.
      #
      # @return [String] frozen binary CopyData payload
      def to_copy_data
        (
          "r".b +
          [received_lsn, flushed_lsn, applied_lsn, client_clock].pack("Q>Q>Q>Q>") +
          [reply_requested ? 1 : 0].pack("C")
        ).freeze
      end

      # Current PostgreSQL protocol timestamp.
      #
      # PostgreSQL timestamps in replication messages are expressed as
      # microseconds since 2000-01-01 00:00:00 UTC, not Unix epoch
      # microseconds.
      #
      # @return [Integer] microseconds since 2000-01-01 UTC
      def self.current_pg_time
        ((Time.now.utc - Time.utc(2000, 1, 1)) * 1_000_000).to_i
      end
    end
  end
end
