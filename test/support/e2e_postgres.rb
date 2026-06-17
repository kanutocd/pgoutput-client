# frozen_string_literal: true

require "securerandom"
require "timeout"

module PgoutputClientE2E
  DEFAULT_DATABASE_URL = "postgres://postgres:postgres@127.0.0.1:55432/pgoutput_client_test"
  WAIT_TIMEOUT = 30

  module_function

  def enabled?
    ENV["PGOUTPUT_CLIENT_E2E"] == "1"
  end

  def database_url
    ENV.fetch("PGOUTPUT_CLIENT_E2E_DATABASE_URL", DEFAULT_DATABASE_URL)
  end

  def skip_unless_enabled!(test_case)
    return if enabled?

    test_case.skip e2e_skip_message
  end

  def e2e_skip_message
    "set PGOUTPUT_CLIENT_E2E=1, run `bundle exec rake e2e:up`, then `bundle exec rake test:e2e`"
  end

  def normal_connection
    require_pg!
    reset_test_pg_stub!
    PG.connect(database_url)
  end

  def reset_test_pg_stub!
    PG.connect_result = nil if PG.respond_to?(:connect_result=)
    PG.connect_error = nil if PG.respond_to?(:connect_error=)
  end

  def unique_name(prefix)
    "#{prefix}_#{SecureRandom.hex(6)}"
  end

  def require_pg!
    require "pg"
  rescue LoadError => e
    raise e if enabled?
  end

  def pg_error_class
    require_pg!
    PG::Error
  end

  def wait_for_postgres!
    Timeout.timeout(WAIT_TIMEOUT) do
      loop do
        connection = normal_connection
        connection.close
        return true
      rescue pg_error_class
        sleep 0.1
      end
    end
  end

  def with_schema
    wait_for_postgres!

    table_name, publication_name, slot_name, connection = build_schema
    schema = { connection:, table_name:, publication_name:, slot_name: }
    yield(schema)
    schema
  ensure
    cleanup_schema(connection, table_name, publication_name)
  end

  def drop_slot(slot_name)
    connection = normal_connection
    connection.exec(<<~SQL)
      SELECT pg_drop_replication_slot('#{slot_name}')
      WHERE EXISTS (
        SELECT 1
        FROM pg_replication_slots
        WHERE slot_name = '#{slot_name}'
      )
    SQL
  ensure
    connection&.close unless connection&.finished?
  end

  def restart_postgres!
    system(
      "docker", "compose", "-f", "docker-compose.e2e.yml",
      "restart", "postgres"
    ) || raise("failed to restart postgres service")
  end

  def build_schema
    table_name = unique_name("widgets")
    publication_name = unique_name("pub")
    slot_name = unique_name("slot")

    connection = normal_connection
    connection.exec(
      %(CREATE TABLE #{table_name} (id bigserial PRIMARY KEY, name text NOT NULL))
    )
    connection.exec(%(CREATE PUBLICATION #{publication_name} FOR TABLE #{table_name}))

    [table_name, publication_name, slot_name, connection]
  end

  def cleanup_schema(connection, table_name, publication_name)
    return unless connection

    cleanup_connection = connection unless connection.finished?
    cleanup_connection ||= normal_connection
    drop_schema_resources(cleanup_connection, table_name, publication_name)
  rescue pg_error_class
    cleanup_connection&.close unless cleanup_connection&.finished?
    cleanup_connection = normal_connection
    drop_schema_resources(cleanup_connection, table_name, publication_name)
  ensure
    cleanup_connection&.close unless cleanup_connection&.finished?
  end

  def drop_schema_resources(connection, table_name, publication_name)
    connection.exec(%(DROP PUBLICATION IF EXISTS #{publication_name})) if publication_name
    connection.exec(%(DROP TABLE IF EXISTS #{table_name})) if table_name
  end
  private_class_method :build_schema, :cleanup_schema, :drop_schema_resources
end
