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
      :retained_wal_bytes,
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
        value = ->(key) { attributes.fetch(key) { attributes[key.to_sym] } }

        new(
          slot_name: value.call("slot_name"), plugin: value.call("plugin"),
          slot_type: value.call("slot_type"), database: value.call("database"),
          active: value.call("active") == true, active_pid: value.call("active_pid"),
          catalog_xmin: value.call("catalog_xmin"), restart_lsn: value.call("restart_lsn"),
          confirmed_flush_lsn: value.call("confirmed_flush_lsn"),
          retained_wal_bytes: value.call("retained_wal_bytes"),
          wal_status: value.call("wal_status"), safe_wal_size: value.call("safe_wal_size"),
          inactive_since: value.call("inactive_since"), conflicting: value.call("conflicting"),
          invalidation_reason: value.call("invalidation_reason")
        )
      end
    end
  end
end
