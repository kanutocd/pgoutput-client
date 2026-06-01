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
    # @api private
    class Stream
      # Build a stream loop.
      #
      # @param connection [Connection] replication connection
      # @param configuration [Configuration] stream configuration
      # @return [void]
      def initialize(connection:, configuration:)
        @connection = connection
        @configuration = configuration
        @latest_lsn = LSN.parse(configuration.start_lsn_string)
        @last_feedback_at = monotonic_time
        @running = false
      end

      # Start the stream loop.
      #
      # The method blocks while the stream is running. For every XLogData
      # envelope, it yields the raw pgoutput payload and the parsed envelope
      # metadata. When no CopyData payload is currently available, the loop
      # continues and checks again.
      #
      # @yield [payload, metadata] called for each XLogData payload
      # @yieldparam payload [String] frozen raw pgoutput payload bytes
      # @yieldparam metadata [XLogData] parsed WAL envelope metadata
      # @return [void]
      # @raise [ArgumentError] if no block is provided
      # @raise [ProtocolError] if an unknown or malformed replication message is
      #   received
      # @raise [ConnectionError] if standby feedback cannot be sent
      def start(&block)
        raise ArgumentError, "block required" unless block_given?

        @running = true
        while @running
          copy_data = @connection.get_copy_data
          next unless copy_data

          process_copy_data(copy_data, &block)
          send_periodic_feedback
        end
      end

      # Stop the stream loop after the current iteration.
      #
      # @return [void]
      def stop
        @running = false
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
        feedback = Feedback.now(received_lsn: @latest_lsn, reply_requested:)
        @connection.put_copy_data(feedback.to_copy_data)
        @last_feedback_at = monotonic_time
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
