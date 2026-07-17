# frozen_string_literal: true

module Pgoutput
  module Client
    # Thin wrapper around `PG::Connection` for logical replication operations.
    #
    # `Connection` hides the small amount of PostgreSQL driver plumbing needed by
    # the rest of the transport layer. It opens the connection in replication
    # mode, renders replication commands through {Commands}, and translates
    # `PG::Error` exceptions into {ConnectionError}.
    #
    # @api private
    class Connection
      # Configuration associated with this connection.
      #
      # @return [Configuration]
      attr_reader :configuration

      # Open a PostgreSQL connection in database replication mode.
      #
      # @param configuration [Configuration] replication configuration
      # @return [Connection] wrapper around an open `PG::Connection`
      # @raise [ConnectionError] if the `pg` gem cannot connect
      def self.open(configuration)
        require "pg"
        connection = PG.connect(configuration.database_url, replication: "database")
        new(configuration:, pg_connection: connection)
      rescue PG::Error => e
        raise ConnectionError, e.message
      end

      # Build a connection wrapper.
      #
      # This constructor is public primarily for tests and alternative connection
      # factories. Normal callers should use {.open}.
      #
      # @param configuration [Configuration] replication configuration
      # @param pg_connection [PG::Connection] connected PostgreSQL driver object
      # @return [void]
      def initialize(configuration:, pg_connection:)
        @configuration = configuration
        @pg_connection = pg_connection
      end

      # Execute PostgreSQL's `IDENTIFY_SYSTEM` replication command.
      #
      # @return [PG::Result] server identity result
      # @raise [ConnectionError] if PostgreSQL rejects the command
      def identify_system
        exec("IDENTIFY_SYSTEM")
      end

      # Create the configured logical replication slot.
      #
      # @return [PG::Result] command result
      # @raise [ConnectionError] if PostgreSQL rejects the command
      def create_replication_slot
        exec(Commands.create_replication_slot(configuration))
      end

      # Drop the configured logical replication slot.
      #
      # @return [PG::Result] command result
      # @raise [ConnectionError] if PostgreSQL rejects the command
      def drop_replication_slot
        exec(Commands.drop_replication_slot(configuration))
      end

      # Start streaming logical replication from the configured slot and LSN.
      #
      # @return [PG::Result] command result
      # @raise [ConnectionError] if PostgreSQL rejects the command
      def start_replication
        exec(Commands.start_replication(configuration))
      end

      # Receive one CopyData payload from the server.
      #
      # The stream must not block forever while PostgreSQL is idle, because the
      # caller needs opportunities to send periodic standby feedback. Wait
      # briefly for socket readability, then use the pg driver's blocking
      # CopyData read only when data is available. `nil` means the stream is
      # currently idle.
      #
      # @return [String, nil] raw CopyData payload or `nil`
      # @raise [ConnectionError] if receiving fails
      def get_copy_data # rubocop:disable Naming/AccessorMethodName
        return nil unless copy_data_readable?

        copy_data = @pg_connection.get_copy_data(false)
        copy_data == false ? nil : copy_data
      rescue PG::Error => e
        raise ConnectionError, e.message
      end

      # Send one CopyData payload to the server.
      #
      # Used for standby status feedback messages.
      #
      # @param payload [String] raw CopyData payload
      # @return [void]
      # @raise [ConnectionError] if sending fails
      def put_copy_data(payload)
        @pg_connection.put_copy_data(payload)
      rescue PG::Error => e
        raise ConnectionError, e.message
      end

      # Close the PostgreSQL connection if it is still open.
      #
      # @return [void]
      def close
        @pg_connection.close unless @pg_connection.finished?
      end

      private

      def copy_data_readable?
        return true unless @pg_connection.respond_to?(:socket_io)

        socket = @pg_connection.socket_io
        return true unless socket

        !!socket.wait_readable(0.1)
      end

      def exec(sql)
        @pg_connection.exec(sql)
      rescue PG::Error => e
        raise ConnectionError, e.message
      end
    end
  end
end
