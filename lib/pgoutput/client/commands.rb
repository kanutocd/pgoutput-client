# frozen_string_literal: true

module Pgoutput
  module Client
    # SQL command builders for PostgreSQL replication-mode commands.
    #
    # PostgreSQL replication commands are issued on a connection opened with the
    # replication parameter enabled. The methods in this module render the small
    # command subset needed by `pgoutput-client` and rely on {Configuration} to
    # validate identifier-like values before interpolation.
    #
    # @api private
    module Commands
      module_function

      # Render a `CREATE_REPLICATION_SLOT` command.
      #
      # Temporary slots are requested only when
      # {Configuration#temporary_slot} is true.
      #
      # @example Permanent slot
      #   Commands.create_replication_slot(config)
      #   # => "CREATE_REPLICATION_SLOT cdc_slot LOGICAL pgoutput"
      #
      # @param configuration [Configuration] replication configuration
      # @return [String] SQL command suitable for `PG::Connection#exec`
      def create_replication_slot(configuration)
        temporary = configuration.temporary_slot ? " TEMPORARY" : ""
        "CREATE_REPLICATION_SLOT #{configuration.slot_name}#{temporary} LOGICAL #{configuration.plugin}"
      end

      # Render a `DROP_REPLICATION_SLOT` command.
      #
      # @param configuration [Configuration] replication configuration
      # @return [String] SQL command suitable for `PG::Connection#exec`
      def drop_replication_slot(configuration)
        "DROP_REPLICATION_SLOT #{configuration.slot_name}"
      end

      # Render a `START_REPLICATION SLOT ... LOGICAL ...` command.
      #
      # The command includes the pgoutput options required by PostgreSQL:
      # `proto_version` and `publication_names`. Optional pgoutput switches such
      # as `binary` and `messages` are emitted only when enabled.
      #
      # @param configuration [Configuration] replication configuration
      # @return [String] SQL command suitable for `PG::Connection#exec`
      def start_replication(configuration)
        options = {
          "proto_version" => configuration.proto_version.to_s,
          "publication_names" => configuration.publication_names.join(","),
          "binary" => configuration.binary ? "true" : nil,
          "messages" => configuration.messages ? "true" : nil
        }.compact

        rendered_options = options.map { |key, value| %("#{key}" '#{value}') }.join(", ")

        "START_REPLICATION SLOT #{configuration.slot_name} LOGICAL #{configuration.start_lsn_string} (#{rendered_options})"
      end
    end
  end
end
