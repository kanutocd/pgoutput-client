# frozen_string_literal: true

module Pgoutput
  module Client
    # High-level logical replication client facade.
    #
    # `Runner` is the simplest public entry point for consumers that want to
    # stream raw pgoutput payloads without manually managing a replication
    # connection. It owns the connection lifecycle for one logical replication
    # stream:
    #
    # 1. Build an immutable {Configuration} from keyword arguments.
    # 2. Open a PostgreSQL replication connection.
    # 3. Optionally create the configured replication slot.
    # 4. Start logical replication.
    # 5. Yield raw pgoutput payload bytes and {XLogData} metadata.
    # 6. Close the connection when streaming exits.
    #
    # If a live stream loses its connection, the runner retries a small number
    # of times with a backoff and resumes from the latest confirmed WAL
    # position. Replay, checkpointing, and deduplication are not owned here;
    # those concerns belong to the downstream CDC runtime and sink layer.
    #
    # @example Stream raw pgoutput messages
    #   runner = Pgoutput::Client::Runner.new(
    #     database_url: "postgres://localhost/app",
    #     slot_name: "cdc_slot",
    #     publication_names: ["app_publication"]
    #   )
    #
    #   runner.start do |payload, metadata|
    #     puts "received #{payload.bytesize} bytes at #{metadata.wal_end_lsn}"
    #   end
    #
    # @see Configuration
    # @see Connection
    # @see Stream
    # @api public
    class Runner
      DEFAULT_RECONNECT_ATTEMPTS = 30
      DEFAULT_RECONNECT_BACKOFF = 0.5

      # Configuration used by this runner.
      #
      # @return [Configuration]
      attr_reader :configuration

      # Last transport error seen by the runner.
      #
      # @return [Exception, nil]
      attr_reader :last_error

      # Build a runner from configuration keyword arguments.
      #
      # The accepted keywords are the same as {Configuration#initialize}. The
      # resulting configuration object is immutable and reused for the lifetime
      # of this runner.
      #
      # @param options [Hash{Symbol=>Object}] configuration options forwarded to
      #   {Configuration#initialize}
      # @return [void]
      # @raise [ConfigurationError] if the supplied configuration is invalid
      def initialize(**options)
        @configuration = Configuration.new(
          **options # : untyped
        )
        @stopped = true
        @running = false
        @stream = nil
        @resume_lsn = configuration.start_lsn
        @acked_lsn = configuration.start_lsn
        @slot_created = false
        @connected_once = false
        @last_error = nil
        @reconnect_attempts = 0
      end

      # Start streaming raw pgoutput payloads.
      #
      # This method blocks until the stream stops or the underlying connection
      # raises an error. The yielded payload is the raw logical decoding plugin
      # payload contained inside PostgreSQL's XLogData envelope; callers normally
      # pass this payload to a pgoutput parser.
      #
      # @yield [payload, metadata] called once for each XLogData payload
      # @yieldparam payload [String] frozen raw pgoutput payload bytes
      # @yieldparam metadata [XLogData] WAL envelope metadata for the payload
      # @return [void]
      # @raise [ArgumentError] if no block is provided
      # @raise [ConnectionError] if a PostgreSQL connection or command fails
      # @raise [ProtocolError] if an invalid replication message is received
      def start(&block)
        raise ArgumentError, "block required" unless block

        @stopped = false
        @running = true
        @last_error = nil
        @reconnect_attempts = 0

        loop do
          current_configuration = configuration_for_resume
          case run_stream_cycle(current_configuration, &block)
          when :done
            break
          when :retry
            @reconnect_attempts += 1
            raise @last_error if @reconnect_attempts > DEFAULT_RECONNECT_ATTEMPTS

            sleep(reconnect_backoff_for(@reconnect_attempts))
          end
        end
      ensure
        @running = false
        @stopped = true
      end

      # Request graceful stop.
      #
      # This method records the caller's intent to stop and asks the active
      # {Stream}, if any, to stop after its current iteration.
      #
      # @return [void]
      def stop
        @stopped = true
        @stream&.stop
        nil
      end

      # Stop the active stream and start again with the same block.
      #
      # The runner is synchronous, so this helper is primarily useful for
      # supervisors that call it instead of manually calling {#stop} followed by
      # {#start}.
      #
      # @yield [payload, metadata] called once for each XLogData payload
      # @return [void]
      def restart(&block)
        stop
        start(&block)
      end

      # Whether the runner is currently inside its streaming loop.
      #
      # @return [Boolean]
      def running?
        @running
      end

      # Whether the runner has stopped.
      #
      # @return [Boolean]
      def stopped?
        !running?
      end

      # Whether an active replication stream exists.
      #
      # @return [Boolean]
      def connected?
        !@stream.nil?
      end

      # Mark a WAL position as durably handled by downstream code.
      #
      # This does not checkpoint or persist anything. It only updates transport
      # feedback state so future standby status updates can distinguish received
      # WAL from downstream-acknowledged WAL.
      #
      # @param lsn [String, Integer] WAL position acknowledged by downstream code
      # @return [Integer] normalized acknowledged WAL position
      def ack(lsn)
        parsed = normalize_lsn_value(lsn)
        @acked_lsn = [@acked_lsn ? normalize_lsn_value(@acked_lsn) : 0, parsed].max
        @stream&.ack(@acked_lsn)
        @acked_lsn
      end

      # Return an immutable transport status snapshot.
      #
      # @return [RunnerState]
      def monitor
        RunnerState.new(
          running: running?,
          stop_requested: @stopped,
          connected: connected?,
          last_received_lsn: current_lsn_string(@stream&.latest_lsn || @resume_lsn),
          last_feedback_lsn: current_lsn_string(@stream&.acked_lsn || @acked_lsn),
          last_keepalive_at: @stream&.last_keepalive_at,
          last_error: @last_error&.message,
          reconnect_attempts: @reconnect_attempts
        )
      end

      private

      def setup_connection(connection)
        ensure_replication_slot(connection) if configuration.auto_create_slot && !@slot_created

        connection.start_replication
      end

      def ensure_replication_slot(connection)
        connection.create_replication_slot
        @slot_created = true
      rescue ConnectionError => e
        raise unless replication_slot_already_exists?(e)

        @slot_created = true
      end

      def replication_slot_already_exists?(error)
        error.message.match?(/replication slot .* already exists/i)
      end

      def run_stream_cycle(configuration, &block)
        connection = Connection.open(configuration)
        setup_connection(connection)
        @connected_once = true
        @stream = Stream.new(connection:, configuration:, acked_lsn: @acked_lsn)
        @stream.start(&block)
        :done
      rescue ConnectionError => e
        @last_error = e
        raise if @stopped
        raise if @stream.nil? && !@connected_once

        @resume_lsn = @stream&.latest_lsn || @resume_lsn
        @acked_lsn = @stream&.acked_lsn || @acked_lsn
        :retry
      ensure
        @stream = nil
        connection&.close
      end

      def configuration_for_resume
        return configuration if @resume_lsn.nil?

        Configuration.new(
          database_url: configuration.database_url,
          slot_name: configuration.slot_name,
          publication_names: configuration.publication_names,
          start_lsn: @resume_lsn,
          proto_version: configuration.proto_version,
          binary: configuration.binary,
          messages: configuration.messages,
          auto_create_slot: configuration.auto_create_slot,
          temporary_slot: configuration.temporary_slot,
          feedback_interval: configuration.feedback_interval
        )
      end

      def normalize_lsn_value(value)
        value.is_a?(String) ? LSN.parse(value) : LSN.parse(LSN.format(value))
      end

      def current_lsn_string(value)
        return nil if value.nil?

        value.is_a?(String) ? value : LSN.format(value)
      end

      def reconnect_backoff_for(attempts)
        DEFAULT_RECONNECT_BACKOFF * attempts
      end

      def sleep(duration)
        Kernel.sleep(duration)
      end
    end
  end
end
