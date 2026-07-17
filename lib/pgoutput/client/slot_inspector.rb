# frozen_string_literal: true

require "json"

module Pgoutput
  module Client
    # Reads PostgreSQL replication-slot catalog state.
    #
    # Inspection uses a short-lived ordinary database connection because
    # catalog queries are separate from the long-lived replication protocol
    # connection. Querying the whole catalog row through `to_jsonb` keeps the
    # result compatible with PostgreSQL versions that expose different optional
    # slot-health columns.
    #
    # @api public
    class SlotInspector
      # Version-tolerant catalog query for one replication slot.
      #
      # @return [String]
      QUERY = <<~SQL
        SELECT
          to_jsonb(slot) || jsonb_build_object(
            'retained_wal_bytes',
            CASE
              WHEN slot.restart_lsn IS NULL THEN NULL
              ELSE pg_wal_lsn_diff(pg_current_wal_lsn(), slot.restart_lsn)::bigint
            END
          ) AS slot
        FROM pg_catalog.pg_replication_slots AS slot
        WHERE slot.slot_name = $1
      SQL

      # @return [String] PostgreSQL connection URL
      attr_reader :database_url

      # @param database_url [String] PostgreSQL connection URL
      # @param connection_factory [#call, nil] optional connection factory for tests
      def initialize(database_url:, connection_factory: nil)
        @database_url = database_url
        @connection_factory = connection_factory
      end

      # Fetch the configured slot's current catalog state.
      #
      # @param slot_name [String] replication slot name
      # @return [SlotStatus, nil] snapshot, or `nil` when the slot is missing
      # @raise [ConnectionError] when PostgreSQL cannot be queried
      def fetch(slot_name)
        connection = open_connection
        row = connection.exec_params(QUERY, [String(slot_name)]).first
        return nil unless row

        SlotStatus.from_catalog(parse_catalog(row.fetch("slot")))
      rescue pg_error_class => e
        raise ConnectionError, e.message
      ensure
        connection&.close unless connection&.finished?
      end

      private

      def open_connection
        return @connection_factory.call(database_url) if @connection_factory

        require "pg"
        PG.connect(database_url)
      end

      def parse_catalog(value)
        return value if value.is_a?(Hash)

        JSON.parse(value)
      end

      def pg_error_class
        require "pg"
        PG::Error
      end
    end
  end
end
