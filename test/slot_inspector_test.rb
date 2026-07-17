# frozen_string_literal: true

require_relative "test_helper"

class SlotInspectorTest < Minitest::Test
  class FakeResult
    def initialize(row)
      @row = row
    end

    def first = @row
  end

  class FakeConnection
    attr_reader :queries
    attr_accessor :finished

    def initialize(row: nil, error: nil)
      @row = row
      @error = error
      @queries = []
      @finished = false
    end

    def exec_params(sql, parameters)
      raise @error if @error

      queries << [sql, parameters]
      FakeResult.new(@row)
    end

    def close
      @closed = true
    end

    def closed? = @closed
    def finished? = finished
  end

  def inspector(connection)
    Pgoutput::Client::SlotInspector.new(
      database_url: "postgres://localhost/app",
      connection_factory: ->(_database_url) { connection }
    )
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def test_fetch_returns_version_tolerant_slot_snapshot
    connection = FakeConnection.new(row: {
                                      "slot" => JSON.generate(
                                        slot_name: "slot1",
                                        plugin: "pgoutput",
                                        slot_type: "logical",
                                        database: "app",
                                        active: true,
                                        active_pid: 123,
                                        catalog_xmin: "900",
                                        restart_lsn: "0/10",
                                        confirmed_flush_lsn: "0/20",
                                        wal_status: "reserved",
                                        safe_wal_size: 4096,
                                        inactive_since: nil,
                                        conflicting: false,
                                        invalidation_reason: nil
                                      )
                                    })

    status = inspector(connection).fetch("slot1")

    assert_instance_of Pgoutput::Client::SlotStatus, status
    assert_equal "slot1", status.slot_name
    assert_equal "pgoutput", status.plugin
    assert_equal "logical", status.slot_type
    assert_equal "0/10", status.restart_lsn
    assert_equal "0/20", status.confirmed_flush_lsn
    assert_equal "reserved", status.wal_status
    assert_equal 4096, status.safe_wal_size
    assert status.active
    assert connection.closed?
    assert_equal ["slot1"], connection.queries.fetch(0).fetch(1)
    assert_match(/to_jsonb\(slot\)/, connection.queries.fetch(0).fetch(0))
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def test_fetch_accepts_decoded_catalog_hash_from_pg_type_maps
    connection = FakeConnection.new(row: {
                                      "slot" => {
                                        "slot_name" => "slot1",
                                        "slot_type" => "logical",
                                        "active" => false
                                      }
                                    })

    status = inspector(connection).fetch("slot1")

    assert_equal "slot1", status.slot_name
    refute status.active
    assert_nil status.wal_status
  end

  def test_fetch_returns_nil_when_slot_is_missing
    connection = FakeConnection.new

    assert_nil inspector(connection).fetch("missing")
    assert connection.closed?
  end

  def test_fetch_wraps_pg_errors_and_closes_connection
    require "pg"
    connection = FakeConnection.new(error: PG::Error.new("catalog unavailable"))

    error = assert_raises(Pgoutput::Client::ConnectionError) do
      inspector(connection).fetch("slot1")
    end

    assert_equal "catalog unavailable", error.message
    assert connection.closed?
  end

  def test_fetch_does_not_close_already_finished_connection
    connection = FakeConnection.new
    connection.finished = true

    inspector(connection).fetch("missing")

    refute connection.closed?
  end
end
