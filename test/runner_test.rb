# frozen_string_literal: true

require_relative "test_helper"

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
      attr_accessor :last_connection, :last_configuration
    end

    def initialize(connection:, configuration:)
      self.class.last_connection = connection
      self.class.last_configuration = configuration
    end

    def start
      yield "payload", :metadata
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
    Pgoutput::Client::Stream.stub(:new, lambda { |connection:, configuration:|
      FakeStream.new(connection:, configuration:)
    }, &block)
  end

  def test_initialize_builds_configuration
    runner = Pgoutput::Client::Runner.new(**options)

    assert_instance_of Pgoutput::Client::Configuration, runner.configuration
    assert_equal "slot1", runner.configuration.slot_name
  end

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
end
