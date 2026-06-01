# frozen_string_literal: true

require_relative "test_helper"

class ConnectionTest < Minitest::Test

  class FakePGConnection
    attr_reader :executed_sql, :copy_data_payloads
    attr_accessor :copy_data_response, :finished, :raise_on

    def initialize
      @executed_sql = []
      @copy_data_payloads = []
      @finished = false
    end

    def exec(sql)
      raise PG::Error, "exec failed" if raise_on == :exec

      executed_sql << sql
      :result
    end

    def get_copy_data(async)
      raise PG::Error, "read failed" if raise_on == :get_copy_data

      raise "expected async false" unless async == false

      copy_data_response
    end

    def put_copy_data(payload)
      raise PG::Error, "write failed" if raise_on == :put_copy_data

      copy_data_payloads << payload
      nil
    end

    def close
      @closed = true
    end

    def closed? = @closed

    def finished? = finished
  end

  def setup
    @configuration = Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: "pub1",
      start_lsn: "0/10"
    )
    @pg_connection = FakePGConnection.new
    @connection = Pgoutput::Client::Connection.new(configuration: @configuration, pg_connection: @pg_connection)
  end

  def setup_pg(connect_result: @pg_connection, connect_error: nil)
    require "pg"
    PG.connect_result = connect_result
    PG.connect_error = connect_error
    PG.last_connect_args = nil
  end


  def test_open_connects_in_database_replication_mode
    setup_pg

    connection = Pgoutput::Client::Connection.open(@configuration)

    assert_instance_of Pgoutput::Client::Connection, connection
    assert_equal ["postgres://localhost/app", "database"], PG.last_connect_args
  end

  def test_open_wraps_pg_error
    require "pg"
    setup_pg(connect_error: PG::Error.new("connect failed"))

    error = assert_raises(Pgoutput::Client::ConnectionError) do
      Pgoutput::Client::Connection.open(@configuration)
    end

    assert_equal "connect failed", error.message
  end

  def test_identify_system_executes_command
    assert_equal :result, @connection.identify_system
    assert_equal ["IDENTIFY_SYSTEM"], @pg_connection.executed_sql
  end

  def test_replication_slot_commands_execute_generated_sql
    @connection.create_replication_slot
    @connection.drop_replication_slot
    @connection.start_replication

    assert_equal(
      [
        "CREATE_REPLICATION_SLOT slot1 LOGICAL pgoutput",
        "DROP_REPLICATION_SLOT slot1",
        "START_REPLICATION SLOT slot1 LOGICAL 0/10 (\"proto_version\" '1', \"publication_names\" 'pub1')"
      ],
      @pg_connection.executed_sql
    )
  end

  def test_get_copy_data_reads_nonblocking_copy_data
    @pg_connection.copy_data_response = "payload"

    assert_equal "payload", @connection.get_copy_data
  end

  def test_put_copy_data_writes_payload
    @connection.put_copy_data("payload")

    assert_equal ["payload"], @pg_connection.copy_data_payloads
  end

  def test_close_closes_unfinished_connection
    @connection.close

    assert @pg_connection.closed?
  end

  def test_close_does_not_close_finished_connection
    @pg_connection.finished = true

    @connection.close

    refute @pg_connection.closed?
  end

  def test_exec_wraps_pg_error
    require "pg"
    @pg_connection.raise_on = :exec
    error = assert_raises(Pgoutput::Client::ConnectionError) { @connection.identify_system }

    assert_equal "exec failed", error.message
  end

  def test_get_copy_data_wraps_pg_error
    require "pg"
    @pg_connection.raise_on = :get_copy_data
    error = assert_raises(Pgoutput::Client::ConnectionError) { @connection.get_copy_data }

    assert_equal "read failed", error.message
  end

  def test_put_copy_data_wraps_pg_error
    require "pg"
    @pg_connection.raise_on = :put_copy_data
    error = assert_raises(Pgoutput::Client::ConnectionError) { @connection.put_copy_data("payload") }

    assert_equal "write failed", error.message
  end
end
