# frozen_string_literal: true

module Pgoutput
  module Client
    # Immutable configuration for a PostgreSQL logical replication stream.
    #
    # A configuration describes how `pgoutput-client` should connect to
    # PostgreSQL and how it should request logical replication from the server.
    # It deliberately contains transport-level settings only; parsing pgoutput
    # records and decoding PostgreSQL values belong to downstream layers.
    #
    # The object freezes itself and its string/array attributes during
    # initialization so it can be safely shared by transport components without
    # defensive copying.
    #
    # @example Minimal configuration
    #   config = Pgoutput::Client::Configuration.new(
    #     database_url: "postgres://localhost/app",
    #     slot_name: "cdc_slot",
    #     publication_names: "app_publication"
    #   )
    #
    # @example Start from a known LSN and request binary values from pgoutput
    #   config = Pgoutput::Client::Configuration.new(
    #     database_url: ENV.fetch("DATABASE_URL"),
    #     slot_name: "cdc_slot",
    #     publication_names: %w[app_publication],
    #     start_lsn: "0/16B6C50",
    #     binary: true
    #   )
    #
    # @api public
    class Configuration
      # Default logical decoding output plugin.
      #
      # @return [String]
      DEFAULT_PLUGIN = "pgoutput"

      # Default pgoutput protocol version.
      #
      # @return [Integer]
      DEFAULT_PROTO_VERSION = 1

      # Default interval, in seconds, between standby status feedback messages.
      #
      # @return [Float]
      DEFAULT_FEEDBACK_INTERVAL = 10.0

      # @!attribute [r] database_url
      #   PostgreSQL connection URL.
      #   @return [String]
      # @!attribute [r] slot_name
      #   Logical replication slot name.
      #   @return [String]
      # @!attribute [r] publication_names
      #   Publication names requested from pgoutput.
      #   @return [Array<String>]
      # @!attribute [r] start_lsn
      #   Optional normalized starting LSN.
      #   @return [String, nil]
      # @!attribute [r] plugin
      #   Logical decoding output plugin name.
      #   @return [String]
      # @!attribute [r] proto_version
      #   pgoutput protocol version.
      #   @return [Integer]
      # @!attribute [r] binary
      #   Whether to request binary column values from pgoutput.
      #   @return [Boolean]
      # @!attribute [r] messages
      #   Whether to request logical decoding messages from pgoutput.
      #   @return [Boolean]
      # @!attribute [r] auto_create_slot
      #   Whether the client should create the slot before streaming.
      #   @return [Boolean]
      # @!attribute [r] temporary_slot
      #   Whether a newly created slot should be temporary.
      #   @return [Boolean]
      # @!attribute [r] feedback_interval
      #   Standby feedback interval in seconds.
      #   @return [Float]
      attr_reader :database_url,
                  :slot_name,
                  :publication_names,
                  :start_lsn,
                  :plugin,
                  :proto_version,
                  :binary,
                  :messages,
                  :auto_create_slot,
                  :temporary_slot,
                  :feedback_interval

      # Build and validate a logical replication stream configuration.
      #
      # `slot_name` and every publication name are intentionally limited to
      # simple PostgreSQL identifier-like strings. This keeps command rendering
      # small and predictable while avoiding quoting rules in this transport
      # layer.
      #
      # Boolean options are normalized with Ruby truthiness. `nil` and `false`
      # become `false`; all other values become `true`.
      #
      # @param database_url [#to_s] PostgreSQL connection URL
      # @param slot_name [#to_s] logical replication slot name
      # @param publication_names [Array<#to_s>, #to_s] one or more publication
      #   names to pass to pgoutput
      # @param start_lsn [String, Integer, nil] starting LSN as a PostgreSQL LSN
      #   string, an integer WAL position, or `nil` for `0/0`
      # @param plugin [#to_s] logical decoding plugin name
      # @param proto_version [#to_int, #to_s] pgoutput protocol version
      # @param binary [Object] truthy to request binary column values
      # @param messages [Object] truthy to request logical decoding messages
      # @param auto_create_slot [Object] truthy to create the slot before
      #   starting replication
      # @param temporary_slot [Object] truthy to create a temporary replication
      #   slot when `auto_create_slot` is enabled
      # @param feedback_interval [#to_f, #to_s] seconds between periodic standby
      #   feedback messages
      # @return [void]
      # @raise [ConfigurationError] if publication names are empty or numeric
      #   settings are invalid
      # @raise [ArgumentError] if `start_lsn`, `proto_version`, or
      #   `feedback_interval` cannot be coerced
      def initialize(database_url:,
                     slot_name:,
                     publication_names:,
                     start_lsn: nil,
                     plugin: DEFAULT_PLUGIN,
                     proto_version: DEFAULT_PROTO_VERSION,
                     binary: false,
                     messages: false,
                     auto_create_slot: false,
                     temporary_slot: false,
                     feedback_interval: DEFAULT_FEEDBACK_INTERVAL)
        @database_url = String(database_url).freeze
        @slot_name = validate_identifier(slot_name, "slot_name").freeze
        @publication_names = Array(publication_names).map do |name|
          validate_identifier(name, "publication_name").freeze
        end.freeze
        @start_lsn = normalize_lsn(start_lsn).freeze
        @plugin = String(plugin).freeze
        @proto_version = Integer(proto_version)
        @binary = boolean(binary, "binary")
        @messages = boolean(messages, "messages")
        @auto_create_slot = boolean(auto_create_slot, "auto_create_slot")
        @temporary_slot = boolean(temporary_slot, "temporary_slot")
        @feedback_interval = Float(feedback_interval)

        validate!
        freeze
      end

      # Starting LSN to render in `START_REPLICATION`.
      #
      # @return [String] normalized LSN string, defaulting to `"0/0"`
      def start_lsn_string
        start_lsn || "0/0"
      end

      private

      def validate!
        raise ConfigurationError, "publication_names must not be empty" if publication_names.empty?
        raise ConfigurationError, "proto_version must be positive" unless proto_version.positive?
        raise ConfigurationError, "feedback_interval must be positive" unless feedback_interval.positive?
      end

      def normalize_lsn(value)
        return nil if value.nil?
        return LSN.format(value) if value.is_a?(Integer)

        LSN.format(LSN.parse(String(value)))
      end

      def validate_identifier(value, field)
        string = String(value)
        unless string.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
          raise ConfigurationError, "#{field} must be a PostgreSQL identifier-like string"
        end

        string
      end

      # Boolean type checking helper
      def boolean(value, name)
        return true if value == true
        return false if value == false

        raise ArgumentError, "#{name} must be true or false"
      end
    end
  end
end
