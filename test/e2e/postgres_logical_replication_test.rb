# frozen_string_literal: true

require "minitest/autorun"
require "pgoutput_client"
require_relative "../support/e2e_postgres"
require "timeout"

class PostgresLogicalReplicationTest < Minitest::Test
  def setup
    PgoutputClientE2E.skip_unless_enabled!(self)
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/BlockLength
  def test_receives_xlog_data_from_real_postgres
    replication_connection = nil
    built_schema = PgoutputClientE2E.with_schema do |schema|
      configuration = Pgoutput::Client::Configuration.new(
        database_url: PgoutputClientE2E.database_url,
        slot_name: schema.fetch(:slot_name),
        publication_names: schema.fetch(:publication_name),
        start_lsn: "0/0",
        auto_create_slot: true,
        feedback_interval: 0.1
      )

      replication_connection = Pgoutput::Client::Connection.open(configuration)
      replication_connection.create_replication_slot
      replication_connection.start_replication

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      schema.fetch(:connection).exec(
        %(INSERT INTO #{schema.fetch(:table_name)} (name) VALUES ('alpha'))
      )

      xlog_data = wait_for_xlog_data(replication_connection)
      elapsed_ms = elapsed_milliseconds_since(started_at)

      send_feedback(replication_connection, xlog_data.wal_end)

      assert_instance_of Pgoutput::Client::XLogData, xlog_data
      assert_operator xlog_data.wal_start, :>=, 0
      assert_operator xlog_data.wal_end, :>, 0
      assert_operator xlog_data.payload.bytesize, :>, 0

      warn format(
        e2e_metrics_format,
        slot: schema.fetch(:slot_name),
        publication: schema.fetch(:publication_name),
        bytes: xlog_data.payload.bytesize,
        start: Pgoutput::Client::LSN.format(xlog_data.wal_start),
        end: Pgoutput::Client::LSN.format(xlog_data.wal_end),
        elapsed: elapsed_ms
      )
    end
  ensure
    replication_connection&.close
    PgoutputClientE2E.drop_slot(built_schema.fetch(:slot_name)) if built_schema&.fetch(:slot_name, nil)
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/BlockLength

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/BlockLength
  def test_recovers_from_postgres_restart_and_resumes_streaming
    runner = nil
    runner_thread = nil
    built_schema = PgoutputClientE2E.with_schema do |schema|
      configuration = Pgoutput::Client::Configuration.new(
        database_url: PgoutputClientE2E.database_url,
        slot_name: schema.fetch(:slot_name),
        publication_names: schema.fetch(:publication_name),
        start_lsn: "0/0",
        auto_create_slot: true,
        feedback_interval: 0.1
      )

      runner = Pgoutput::Client::Runner.new(
        database_url: configuration.database_url,
        slot_name: configuration.slot_name,
        publication_names: configuration.publication_names,
        start_lsn: configuration.start_lsn,
        auto_create_slot: configuration.auto_create_slot,
        feedback_interval: configuration.feedback_interval
      )
      payloads = Queue.new
      payload_count = 0
      payload_count_mutex = Mutex.new

      runner_thread = Thread.new do
        runner.start do |payload, metadata|
          payloads << [payload, metadata]
          payload_count_mutex.synchronize do
            payload_count += 1
            runner.stop if payload_count >= 2
          end
        end
      end

      schema.fetch(:connection).exec(
        %(INSERT INTO #{schema.fetch(:table_name)} (name) VALUES ('alpha'))
      )
      begin
        first_payload, first_metadata = wait_for_payload(payloads)
      rescue Timeout::Error
        PgoutputClientE2E.restart_postgres!
        PgoutputClientE2E.wait_for_postgres!
      end

      PgoutputClientE2E.normal_connection.exec(
        %(INSERT INTO #{schema.fetch(:table_name)} (name) VALUES ('beta'))
      )

      second_payload, second_metadata = wait_for_payload(payloads)

      runner.stop
      runner_thread.value

      assert_instance_of Pgoutput::Client::XLogData, first_metadata
      assert_instance_of Pgoutput::Client::XLogData, second_metadata
      refute_equal first_payload, second_payload
      assert_operator second_metadata.wal_end, :>, first_metadata.wal_end
    end
  ensure
    runner&.stop
    runner_thread&.join
    PgoutputClientE2E.drop_slot(built_schema.fetch(:slot_name)) if built_schema&.fetch(:slot_name, nil)
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/BlockLength

  private

  def send_feedback(replication_connection, lsn)
    feedback = Pgoutput::Client::Feedback.now(
      received_lsn: lsn,
      flushed_lsn: lsn,
      applied_lsn: lsn
    )
    replication_connection.put_copy_data(feedback.to_copy_data)
  end

  def elapsed_milliseconds_since(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
  end

  def e2e_metrics_format
    "E2E PostgreSQL PASS " \
      "slot=%<slot>s " \
      "publication=%<publication>s " \
      "payload_bytes=%<bytes>d " \
      "wal_start=%<start>s " \
      "wal_end=%<end>s " \
      "time_to_first_xlog_ms=%<elapsed>.2f"
  end

  def wait_for_xlog_data(replication_connection)
    Timeout.timeout(PgoutputClientE2E::WAIT_TIMEOUT) do
      loop do
        copy_data = replication_connection.get_copy_data
        return Pgoutput::Client::XLogData.parse(copy_data) if copy_data&.getbyte(0) == "w".ord

        sleep 0.01
      end
    end
  end

  def wait_for_payload(queue)
    Timeout.timeout(PgoutputClientE2E::WAIT_TIMEOUT) do
      queue.pop
    end
  end
end
