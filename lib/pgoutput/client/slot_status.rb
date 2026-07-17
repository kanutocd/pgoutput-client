# frozen_string_literal: true

module Pgoutput
  module Client
    # Immutable snapshot of one PostgreSQL logical replication slot.
    #
    # Fields introduced by newer PostgreSQL versions are `nil` when the server
    # does not expose them. The client reports transport/catalog state only;
    # downstream runtimes remain responsible for deciding whether a checkpoint
    # can safely resume from this slot.
    #
    # @api public
    SlotStatusData = Data.define(
      :slot_name,
      :plugin,
      :slot_type,
      :database,
      :active,
      :active_pid,
      :catalog_xmin,
      :restart_lsn,
      :confirmed_flush_lsn,
      :wal_status,
      :safe_wal_size,
      :inactive_since,
      :conflicting,
      :invalidation_reason
    )

    # Typed replication-slot catalog snapshot.
    #
    # @api public
    class SlotStatus < SlotStatusData
      # Build a snapshot from a `pg_replication_slots` JSON object.
      #
      # @param attributes [Hash{String, Symbol=>Object}] catalog attributes
      # @return [SlotStatus]
      def self.from_catalog(attributes)
        fetch = lambda do |key|
          next attributes[key] if attributes.key?(key)

          attributes[key.to_sym]
        end

        new(
          slot_name: fetch.call("slot_name"),
          plugin: fetch.call("plugin"),
          slot_type: fetch.call("slot_type"),
          database: fetch.call("database"),
          active: fetch.call("active") == true,
          active_pid: fetch.call("active_pid"),
          catalog_xmin: fetch.call("catalog_xmin"),
          restart_lsn: fetch.call("restart_lsn"),
          confirmed_flush_lsn: fetch.call("confirmed_flush_lsn"),
          wal_status: fetch.call("wal_status"),
          safe_wal_size: fetch.call("safe_wal_size"),
          inactive_since: fetch.call("inactive_since"),
          conflicting: fetch.call("conflicting"),
          invalidation_reason: fetch.call("invalidation_reason")
        )
      end
    end
  end
end
