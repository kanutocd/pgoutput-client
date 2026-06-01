# frozen_string_literal: true

require_relative "client/version"
require_relative "client/errors"
require_relative "client/configuration"
require_relative "client/lsn"
require_relative "client/xlog_data"
require_relative "client/keepalive"
require_relative "client/feedback"
require_relative "client/commands"
require_relative "client/connection"
require_relative "client/stream"

module Pgoutput
  # Namespace for PostgreSQL logical replication transport support.
  #
  # `Pgoutput::Client` is the replication transport layer of the CDC Ecosystem.
  # It is responsible for connecting to PostgreSQL in replication mode, creating
  # or consuming replication slots, issuing `START_REPLICATION`, reading CopyData
  # messages, and sending standby feedback.
  #
  # This namespace intentionally does not parse pgoutput plugin payloads into
  # table-level changes. Raw plugin bytes are yielded to downstream protocol and
  # type layers such as `pgoutput-parser` and `pgoutput-decoder`.
  #
  # @api public
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
      # Configuration used by this runner.
      #
      # @return [Configuration]
      attr_reader :configuration

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
        @stopped = false
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

        connection = Connection.open(configuration)
        setup_connection(connection)
        Stream.new(connection:, configuration:).start { |payload, metadata| block.call(payload, metadata) }
      ensure
        connection&.close
      end

      # Request graceful stop.
      #
      # This method records the caller's intent to stop. The current
      # implementation does not yet interrupt an active {Stream}; it exists as
      # part of the public lifecycle API and may be wired into cooperative stream
      # shutdown in a future release.
      #
      # @return [void]
      def stop
        @stopped = true
        nil
      end

      private

      def setup_connection(connection)
        connection.create_replication_slot if configuration.auto_create_slot
        connection.start_replication
      end
    end
  end
end
