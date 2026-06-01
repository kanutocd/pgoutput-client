# frozen_string_literal: true

# Main convenience require for pgoutput-client.
#
# Requiring this file loads the public `Pgoutput::Client` namespace and its
# transport-layer classes.
#
# @example
#   require "pgoutput_client"
#
# @see Pgoutput::Client
require_relative "pgoutput/client"
