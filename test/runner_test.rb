# frozen_string_literal: true

require_relative "test_helper"

# rubocop:disable Metrics/ClassLength
class RunnerTest < Minitest::Test
  class FakeConnection
    attr_reader :calls

    def initialize
      @calls = []
    end

    def create_replication_slot
      calls << :create_replication_slot
    end

    def start_replication
      calls << :start_replication
    end

    def close
      calls << :close
    end
  end

  class FakeStream
    class << self
      attr_accessor :last_connection, :last_configuration, :last_instance
    end

    attr_reader :stopped, :latest_lsn, :acked_lsn, :last_keepalive_at

    def initialize(connection:, configuration:, _acked_lsn: nil)
      self.class.last_connection = connection
      self.class.last_configuration = configuration
      self.class.last_instance = self
      @stopped = false
      @latest_lsn = Pgoutput::Client::LSN.parse("0/20")
      @acked_lsn = Pgoutput::Client::LSN.parse("0/10")
      @last_keepalive_at = Time.utc(2026, 1, 1)
    end

    def start
      yield "payload", :metadata
    end

    def stop
      @stopped = true
    end

    def ack(lsn)
      @acked_lsn = Pgoutput::Client::LSN.parse(Pgoutput::Client::LSN.format(lsn))
    end
  end

  class RetryableStream
    class << self
      attr_accessor :configurations
    end

    attr_reader :latest_lsn, :acked_lsn

    def self.parse_lsn(value)
      return Pgoutput::Client::LSN.parse(value) if value.is_a?(String)

      Pgoutput::Client::LSN.parse(Pgoutput::Client::LSN.format(value))
    end

    def initialize(connection:, configuration:, acked_lsn: nil)
      self.class.configurations ||= []
      self.class.configurations << configuration
      @connection = connection
      @configuration = configuration
      @acked_lsn = if acked_lsn
                     self.class.parse_lsn(acked_lsn)
                   else
                     Pgoutput::Client::LSN.parse(configuration.start_lsn_string)
                   end
      @latest_lsn = Pgoutput::Client::LSN.parse(configuration.start_lsn_string)
      @attempt = self.class.configurations.length
    end

    def start
      if @attempt == 1
        @latest_lsn = Pgoutput::Client::LSN.parse("0/20")
        yield "first", :first_metadata
        raise Pgoutput::Client::ConnectionError, "stream dropped"
      end

      yield "second", :second_metadata
    end
  end

  class AlwaysFailingStream
    attr_reader :latest_lsn, :acked_lsn

    def initialize(connection:, configuration:, acked_lsn: nil)
      @connection = connection
      @configuration = configuration
      @acked_lsn = acked_lsn
      @latest_lsn = Pgoutput::Client::LSN.parse(configuration.start_lsn_string)
    end

    def start
      raise Pgoutput::Client::ConnectionError, "stream still down"
    end
  end

  class StopThenFailStream
    attr_reader :latest_lsn, :acked_lsn

    def initialize(connection:, configuration:, acked_lsn: nil)
      @connection = connection
      @configuration = configuration
      @acked_lsn = acked_lsn
      @latest_lsn = Pgoutput::Client::LSN.parse(configuration.start_lsn_string)
    end

    def start
      yield "payload", :metadata
      raise Pgoutput::Client::ConnectionError, "stopped stream failed"
    end

    def stop
      nil
    end
  end

  class RetryingRunner < Pgoutput::Client::Runner
    attr_reader :sleep_calls

    def initialize(**options)
      @sleep_calls = []
      super
    end

    def sleep(duration)
      sleep_calls << duration
    end
  end

  def options(**overrides)
    {
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: "pub1",
      **overrides
    }
  end

  def with_fake_stream(&block)
    Pgoutput::Client::Stream.stub(:new, lambda { |connection:, configuration:, **|
      FakeStream.new(connection:, configuration:)
    }, &block)
  end

  def test_initialize_builds_configuration
    runner = Pgoutput::Client::Runner.new(**options)

    assert_instance_of Pgoutput::Client::Configuration, runner.configuration
    assert_equal "slot1", runner.configuration.slot_name
  end

  def test_lifecycle_state_defaults_to_stopped
    runner = Pgoutput::Client::Runner.new(**options(start_lsn: "0/10"))

    assert_predicate runner, :stopped?
    refute_predicate runner, :running?
    refute_predicate runner, :connected?

    state = runner.monitor
    assert_predicate state, :stopped?
    assert_equal "0/10", state.last_received_lsn
    assert_equal "0/10", state.last_feedback_lsn
    assert_equal 0, state.reconnect_attempts
  end

  def test_ack_uses_zero_baseline_when_no_start_lsn
    runner = Pgoutput::Client::Runner.new(**options)

    assert_equal Pgoutput::Client::LSN.parse("0/30"), runner.ack(0x30)
    assert_equal "0/30", runner.monitor.last_feedback_lsn
  end

  def test_monitor_reports_active_stream_state
    fake_connection = FakeConnection.new
    runner = Pgoutput::Client::Runner.new(**options(start_lsn: "0/10"))
    snapshots = []

    Pgoutput::Client::Connection.stub(:open, fake_connection) do
      with_fake_stream do
        runner.start do |_payload, _metadata|
          snapshots << runner.monitor
          runner.ack(0x40)
          runner.stop
        end
      end
    end

    state = snapshots.fetch(0)
    assert state.running
    assert state.connected
    assert_equal "0/20", state.last_received_lsn
    assert_equal "0/10", state.last_feedback_lsn
    assert_equal Time.utc(2026, 1, 1), state.last_keepalive_at
    assert_equal "0/40", runner.monitor.last_feedback_lsn
  end

  def test_start_raises_after_reconnect_attempts_are_exhausted
    fake_connection = FakeConnection.new
    runner = RetryingRunner.new(**options(start_lsn: "0/10"))

    error = assert_raises(Pgoutput::Client::ConnectionError) do
      Pgoutput::Client::Connection.stub(:open, fake_connection) do
        Pgoutput::Client::Stream.stub(:new, lambda { |connection:, configuration:, **kwargs|
          AlwaysFailingStream.new(connection:, configuration:, **kwargs)
        }) do
          runner.start { |_payload, _metadata| }
        end
      end
    end

    assert_equal "stream still down", error.message
    assert_equal 30, runner.sleep_calls.length
    assert_equal 0.5, runner.sleep_calls.first
    assert_equal 15.0, runner.sleep_calls.last
    assert_equal 31, fake_connection.calls.count(:start_replication)
    assert_equal "stream still down", runner.monitor.last_error
  end

  def test_stop_requested_connection_error_is_not_retried
    fake_connection = FakeConnection.new
    runner = RetryingRunner.new(**options(start_lsn: "0/10"))

    error = assert_raises(Pgoutput::Client::ConnectionError) do
      Pgoutput::Client::Connection.stub(:open, fake_connection) do
        Pgoutput::Client::Stream.stub(:new, lambda { |connection:, configuration:, **kwargs|
          StopThenFailStream.new(connection:, configuration:, **kwargs)
        }) do
          runner.start { |_payload, _metadata| runner.stop }
        end
      end
    end

    assert_equal "stopped stream failed", error.message
    assert_empty runner.sleep_calls
    assert_equal 1, fake_connection.calls.count(:start_replication)
  end

  def test_connection_open_error_is_exposed_as_last_error
    runner = Pgoutput::Client::Runner.new(**options)

    error = assert_raises(Pgoutput::Client::ConnectionError) do
      Pgoutput::Client::Connection.stub(:open, proc { raise Pgoutput::Client::ConnectionError, "cannot connect" }) do
        runner.start { |_payload, _metadata| }
      end
    end

    assert_equal "cannot connect", error.message
    assert_equal "cannot connect", runner.monitor.last_error
  end

  def test_ack_updates_feedback_lsn_without_stream
    runner = Pgoutput::Client::Runner.new(**options(start_lsn: "0/10"))

    assert_equal Pgoutput::Client::LSN.parse("0/30"), runner.ack("0/30")
    assert_equal "0/30", runner.monitor.last_feedback_lsn
  end

  # rubocop:disable Metrics/MethodLength
  def test_retries_connection_open_errors_after_a_prior_successful_stream
    attempts = 0
    yielded = []
    RetryableStream.configurations = []
    runner = RetryingRunner.new(**options(start_lsn: "0/10"))

    opener = lambda do |_configuration|
      attempts += 1
      raise Pgoutput::Client::ConnectionError, "postgres restarting" if attempts == 2

      FakeConnection.new
    end

    stream_factory = lambda do |connection:, configuration:, **kwargs|
      if attempts == 1
        RetryableStream.new(connection:, configuration:, **kwargs)
      else
        FakeStream.new(connection:, configuration:)
      end
    end

    Pgoutput::Client::Connection.stub(:open, opener) do
      Pgoutput::Client::Stream.stub(:new, stream_factory) do
        runner.start do |payload, metadata|
          yielded << [payload, metadata]
          runner.stop if yielded.length >= 2
        end
      end
    end

    assert_equal 3, attempts
    assert_equal [0.5, 1.0], runner.sleep_calls
    assert_equal [["first", :first_metadata], ["payload", :metadata]], yielded
    assert_equal "postgres restarting", runner.monitor.last_error
  end
  # rubocop:enable Metrics/MethodLength

  def test_start_requires_block
    runner = Pgoutput::Client::Runner.new(**options)

    assert_raises(ArgumentError) { runner.start }
  end

  def test_start_opens_connection_starts_replication_streams_and_closes
    fake_connection = FakeConnection.new
    yielded = []

    Pgoutput::Client::Connection.stub(:open, fake_connection) do
      with_fake_stream do
        Pgoutput::Client::Runner.new(**options).start { |payload, metadata| yielded << [payload, metadata] }
      end
    end

    assert_equal %i[start_replication close], fake_connection.calls
    assert_equal [["payload", :metadata]], yielded
    assert_same fake_connection, FakeStream.last_connection
  end

  def test_start_creates_slot_when_configured
    fake_connection = FakeConnection.new

    Pgoutput::Client::Connection.stub(:open, fake_connection) do
      with_fake_stream do
        Pgoutput::Client::Runner.new(**options(auto_create_slot: true)).start { |_payload, _metadata| }
      end
    end

    assert_equal %i[create_replication_slot start_replication close], fake_connection.calls
  end

  def test_stop_returns_nil
    assert_nil Pgoutput::Client::Runner.new(**options).stop
  end

  def test_stop_requests_active_stream_stop
    fake_connection = FakeConnection.new
    runner = Pgoutput::Client::Runner.new(**options)

    Pgoutput::Client::Connection.stub(:open, fake_connection) do
      with_fake_stream do
        runner.start { |_payload, _metadata| runner.stop }
      end
    end

    assert_predicate FakeStream.last_instance, :stopped
  end

  def test_start_retries_stream_connection_errors_with_resume_lsn
    fake_connection = FakeConnection.new
    yielded = []
    RetryableStream.configurations = []
    runner = RetryingRunner.new(**options(start_lsn: "0/10", auto_create_slot: true))

    Pgoutput::Client::Connection.stub(:open, fake_connection) do
      Pgoutput::Client::Stream.stub(:new, lambda { |connection:, configuration:, **kwargs|
        RetryableStream.new(connection:, configuration:, **kwargs)
      }) do
        runner.start { |payload, metadata| yielded << [payload, metadata] }
      end
    end

    assert_equal [["first", :first_metadata], ["second", :second_metadata]], yielded
    assert_equal [0.5], runner.sleep_calls
    assert_equal ["0/10", "0/20"], RetryableStream.configurations.map(&:start_lsn)
    assert_equal 1, fake_connection.calls.count(:create_replication_slot)
    assert_equal 2, fake_connection.calls.count(:start_replication)
  end
end
# rubocop:enable Metrics/ClassLength
