# frozen_string_literal: true

module Pgoutput
  module Client
    RunnerStateData = Data.define(
      :running,
      :stop_requested,
      :connected,
      :last_received_lsn,
      :last_feedback_lsn,
      :last_keepalive_at,
      :last_error,
      :reconnect_attempts
    )

    # Immutable operational snapshot for a {Runner}.
    #
    # `RunnerState` is intentionally small and transport-focused. It exposes
    # connection, feedback, keepalive, and retry state without claiming anything
    # about downstream processing, sink delivery, or business-level consumption.
    #
    # @attr_reader running [Boolean] whether the runner is inside its streaming loop
    # @attr_reader stop_requested [Boolean] whether graceful stop was requested
    # @attr_reader connected [Boolean] whether an active replication stream exists
    # @attr_reader last_received_lsn [String, nil] latest WAL position received from PostgreSQL
    # @attr_reader last_feedback_lsn [String, nil] latest downstream-acknowledged WAL position
    #   used for flushed/applied feedback
    # @attr_reader last_keepalive_at [Time, nil] last time a primary keepalive was observed
    # @attr_reader last_error [String, nil] last transport error message
    # @attr_reader reconnect_attempts [Integer] reconnect attempts used by the current/last run
    # @api public
    class RunnerState < RunnerStateData
      # Whether the runner currently has no active stream.
      #
      # @return [Boolean]
      def stopped?
        !running
      end
    end
  end
end
