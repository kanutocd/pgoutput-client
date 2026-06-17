# frozen_string_literal: true

require_relative "test_helper"

class StreamTest < Minitest::Test
  class FakeConnection
    attr_reader :sent_payloads

    def initialize(copy_data)
      @copy_data = copy_data.dup
      @sent_payloads = []
    end

    def get_copy_data # rubocop:disable Naming/AccessorMethodName
      @copy_data.shift
    end

    def put_copy_data(payload)
      @sent_payloads << payload
    end
  end

  class OneShotStream < Pgoutput::Client::Stream
    def initialize(**)
      @ticks = [0.0, 20.0, 20.0, 20.0, 40.0]
      super
    end

    def monotonic_time
      @ticks.shift || 40.0
    end
  end

  class IdlePollingStream < Pgoutput::Client::Stream
    attr_reader :sleep_calls

    def initialize(**)
      @sleep_calls = []
      super
    end

    def sleep(duration)
      sleep_calls << duration
    end
  end

  def config(feedback_interval: 10.0, start_lsn: "0/10")
    Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: "pub1",
      start_lsn: start_lsn,
      feedback_interval: feedback_interval
    )
  end

  def xlog_payload(wal_start: 0x10, wal_end: 0x20, body: "payload")
    "w".b + [wal_start, wal_end, 0].pack("Q>Q>Q>") + body.b
  end

  def keepalive_payload(wal_end: 0x30, reply_requested: false)
    "k".b + [wal_end, 0].pack("Q>Q>") + [reply_requested ? 1 : 0].pack("C")
  end

  def unpack_feedback_lsn(payloads)
    payloads.last.byteslice(1, 24).unpack("Q>Q>Q>")
  end

  def test_start_requires_block
    stream = Pgoutput::Client::Stream.new(connection: FakeConnection.new([]), configuration: config)

    assert_raises(ArgumentError) { stream.start }
  end

  def test_processes_xlog_data_and_sends_periodic_feedback
    connection = FakeConnection.new([xlog_payload])
    stream = OneShotStream.new(connection: connection, configuration: config)
    received = []

    stream.start do |payload, metadata|
      received << [payload, metadata.wal_end]
      stream.stop
    end

    assert_equal [["payload", 0x20]], received
    assert_equal 2, connection.sent_payloads.length
    assert_equal "r".ord, connection.sent_payloads.first.getbyte(0)
  end

  def test_feedback_uses_acknowledged_lsn_for_flushed_and_applied_positions
    connection = FakeConnection.new([xlog_payload(wal_start: 0x10, wal_end: 0x30, body: "done")])
    stream = OneShotStream.new(connection: connection, configuration: config(start_lsn: "0/10"))

    stream.start do |_payload, metadata|
      stream.ack(metadata.wal_end)
      stream.stop
    end

    assert_equal [0x30, 0x30, 0x30], unpack_feedback_lsn(connection.sent_payloads)
  end

  def test_feedback_does_not_apply_unacknowledged_received_lsn
    connection = FakeConnection.new([xlog_payload(wal_start: 0x10, wal_end: 0x30, body: "done")])
    stream = OneShotStream.new(connection: connection, configuration: config(start_lsn: "0/10"))

    stream.start do
      stream.stop
    end

    assert_equal [0x30, 0x10, 0x10], unpack_feedback_lsn(connection.sent_payloads)
  end

  def test_keepalive_reply_request_sends_immediate_feedback
    connection = FakeConnection.new([keepalive_payload(reply_requested: true), xlog_payload(body: "done")])
    stream = OneShotStream.new(connection: connection, configuration: config(feedback_interval: 1000.0))

    stream.start do
      stream.stop
    end

    assert_equal 2, connection.sent_payloads.length
    assert_equal 1, connection.sent_payloads.first.getbyte(-1)
  end

  def test_keepalive_without_reply_request_does_not_send_immediate_feedback
    connection = FakeConnection.new([keepalive_payload(reply_requested: false), xlog_payload(body: "done")])
    stream = OneShotStream.new(connection: connection, configuration: config(feedback_interval: 1000.0))

    stream.start do
      stream.stop
    end

    assert_equal 1, connection.sent_payloads.length
  end

  def test_unknown_message_raises_protocol_error
    connection = FakeConnection.new(["?".b])
    stream = OneShotStream.new(connection: connection, configuration: config)

    error = assert_raises(Pgoutput::Client::ProtocolError) do
      stream.start { |_payload, _metadata| }
    end

    assert_equal "unknown CopyData replication message: 63", error.message
  end

  def test_nil_copy_data_can_be_stopped_from_connection
    connection = Class.new(FakeConnection) do
      attr_writer :stream

      def get_copy_data # rubocop:disable Naming/AccessorMethodName
        @stream.stop
        nil
      end
    end.new([])
    stream = Pgoutput::Client::Stream.new(connection: connection, configuration: config)
    connection.stream = stream

    stream.start { flunk "no payload should be yielded" }
  end

  def test_nil_copy_data_yields_idle_pause_before_retrying
    connection = FakeConnection.new([nil, xlog_payload(body: "done")])
    stream = IdlePollingStream.new(connection: connection, configuration: config(feedback_interval: 1000.0))

    stream.start do
      stream.stop
    end

    assert_equal [0.01], stream.sleep_calls
  end

  def test_idle_stream_sends_periodic_feedback_without_xlog_data
    connection = FakeConnection.new([nil, nil, xlog_payload(body: "done")])
    stream_class = Class.new(IdlePollingStream) do
      def initialize(**)
        @ticks = [0.0, 0.25, 0.75, 0.75, 0.75, 0.75]
        super
      end

      def monotonic_time
        @ticks.shift || 0.75
      end
    end
    stream = stream_class.new(connection: connection, configuration: config(feedback_interval: 0.5))

    stream.start do
      stream.stop
    end

    assert_equal [0.01, 0.01], stream.sleep_calls
    assert_equal 2, connection.sent_payloads.length
    assert_equal "r".ord, connection.sent_payloads.first.getbyte(0)
    assert_equal [0x10, 0x10, 0x10], connection.sent_payloads.first.byteslice(1, 24).unpack("Q>Q>Q>")
  end

  def test_initialize_accepts_string_acknowledged_lsn
    stream = Pgoutput::Client::Stream.new(
      connection: FakeConnection.new([]),
      configuration: config(start_lsn: "0/10"),
      acked_lsn: "0/30"
    )

    assert_equal Pgoutput::Client::LSN.parse("0/30"), stream.acked_lsn
  end

  def test_ack_accepts_string_lsn_and_never_moves_backward
    stream = Pgoutput::Client::Stream.new(
      connection: FakeConnection.new([]),
      configuration: config(start_lsn: "0/20")
    )

    assert_equal Pgoutput::Client::LSN.parse("0/40"), stream.ack("0/40")
    assert_equal Pgoutput::Client::LSN.parse("0/40"), stream.ack("0/30")
  end

  def test_clean_loop_exit_without_stop_request_does_not_send_final_feedback
    connection = FakeConnection.new([xlog_payload(body: "done")])
    stream = Pgoutput::Client::Stream.new(
      connection: connection,
      configuration: config(feedback_interval: 1000.0)
    )

    stream.start do
      stream.instance_variable_set(:@running, false)
    end

    assert_empty connection.sent_payloads
    refute_predicate stream, :running?
  end
end
