# frozen_string_literal: true

module Pgoutput
  module Client
    # Logical replication stream loop.
    #
    # `Stream` consumes PostgreSQL CopyData payloads from a {Connection}. It
    # understands the two replication envelope message types used by PostgreSQL's
    # streaming replication protocol:
    #
    # * `w` — XLogData, containing logical decoding plugin payload bytes.
    # * `k` — primary keepalive, optionally requesting immediate feedback.
    #
    # The stream yields only XLogData plugin payloads. Keepalive messages are
    # handled internally by updating the latest known WAL position and sending
    # standby feedback when requested.
    #
    # Feedback separates receipt from downstream acknowledgment. Received LSN
    # follows the latest WAL position seen from PostgreSQL. Flushed/applied LSN
    # follows {#ack}, allowing downstream consumers to decide when a WAL position
    # is safe to report as durable.
    #
    # @api private
    class Stream
      # Latest WAL position observed from XLogData or keepalive messages.
      #
      # @return [Integer]
      attr_reader :latest_lsn

      # Latest downstream-acknowledged WAL position used as flushed/applied LSN
      # in standby feedback.
      #
      # @return [Integer]
      attr_reader :acked_lsn

      # Last time a primary keepalive was observed.
      #
      # @return [Time, nil]
      attr_reader :last_keepalive_at

      # Build a stream loop.
      #
      # @param connection [Connection] replication connection
      # @param configuration [Configuration] stream configuration
      # @param acked_lsn [String, Integer, nil] initial downstream-acknowledged
      #   WAL position
      # @return [void]
      def initialize(connection:, configuration:, acked_lsn: nil)
        @connection = connection
        @configuration = configuration
        @latest_lsn = LSN.parse(configuration.start_lsn_string)
        @acked_lsn = acked_lsn ? normalize_lsn_value(acked_lsn) : @latest_lsn
        @last_feedback_at = monotonic_time
        @last_keepalive_at = nil
        @running = false
        @stop_requested = false
      end

      # Start the stream loop.
      #
      # The method blocks while the stream is running. For every XLogData
      # envelope, it yields the raw pgoutput payload and the parsed envelope
      # metadata. When no CopyData payload is currently available, the loop
      # pauses briefly before checking again.
      #
      # @yield [payload, metadata] called for each XLogData payload
      # @yieldparam payload [String] frozen raw pgoutput payload bytes
      # @yieldparam metadata [XLogData] parsed WAL envelope metadata
      # @return [void]
      # @raise [ArgumentError] if no block is provided
      # @raise [ProtocolError] if an unknown or malformed replication message is
      #   received
      # @raise [ConnectionError] if standby feedback cannot be sent
      def start(&)
        raise ArgumentError, "block required" unless block_given?

        @running = true
        while @running
          copy_data = @connection.get_copy_data
          if copy_data.nil?
            send_periodic_feedback
            sleep 0.01
            next
          end

          process_copy_data(copy_data, &)
          send_periodic_feedback
        end
      ensure
        send_feedback(reply_requested: false) if @stop_requested
        @running = false
      end

      # Stop the stream loop after the current iteration.
      #
      # @return [void]
      def stop
        @stop_requested = true
        @running = false
        nil
      end

      # Whether the stream loop is active.
      #
      # @return [Boolean]
      def running?
        @running
      end

      # Mark a WAL position as durably handled by downstream code.
      #
      # The stream never decides sink durability on its own. Downstream code may
      # call this after checkpointing, enqueueing, or otherwise making progress
      # durable. Feedback sent after this call reports the acknowledged LSN as
      # both flushed and applied.
      #
      # @param lsn [String, Integer] WAL position acknowledged by downstream code
      # @return [Integer] normalized acknowledged WAL position
      def ack(lsn)
        parsed = normalize_lsn_value(lsn)
        @acked_lsn = [@acked_lsn, parsed].max
      end

      private

      def process_copy_data(copy_data)
        case copy_data.getbyte(0)
        when "w".ord
          xlog = XLogData.parse(copy_data)
          @latest_lsn = xlog.wal_end
          yield xlog.payload, xlog
        when "k".ord
          keepalive = Keepalive.parse(copy_data)
          @latest_lsn = [@latest_lsn, keepalive.wal_end].max
          @last_keepalive_at = Time.now.utc
          send_feedback(reply_requested: true) if keepalive.reply_requested
        else
          raise ProtocolError, "unknown CopyData replication message: #{copy_data.getbyte(0).inspect}"
        end
      end

      def send_periodic_feedback
        return if monotonic_time - @last_feedback_at < @configuration.feedback_interval

        send_feedback(reply_requested: false)
      end

      def send_feedback(reply_requested:)
        feedback = Feedback.now(received_lsn: @latest_lsn, flushed_lsn: @acked_lsn, applied_lsn: @acked_lsn,
                                reply_requested:)
        @connection.put_copy_data(feedback.to_copy_data)
        @last_feedback_at = monotonic_time
      end

      def normalize_lsn_value(value)
        value.is_a?(String) ? LSN.parse(value) : LSN.parse(LSN.format(value))
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
