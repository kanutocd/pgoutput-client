# frozen_string_literal: true

require_relative "client/version"
require_relative "client/errors"
require_relative "client/configuration"
require_relative "client/lsn"
require_relative "client/xlog_data"
require_relative "client/keepalive"
require_relative "client/feedback"
require_relative "client/state"
require_relative "client/slot_status"
require_relative "client/slot_inspector"
require_relative "client/commands"
require_relative "client/connection"
require_relative "client/stream"
require_relative "client/runner"

# Namespace for PostgreSQL pgoutput logical replication components.
#
# The top-level namespace is shared by pgoutput ecosystem gems. This gem
# defines only the `Pgoutput::Client` transport namespace and leaves protocol
# parsing, value decoding, and CDC normalization to sibling libraries.
#
# @api public
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
  end
end
