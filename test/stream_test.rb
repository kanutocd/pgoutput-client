# frozen_string_literal: true

require "test_helper"

class FakeConnection
  attr_reader :sent

  def initialize(messages)
    @messages = messages.dup
    @sent = []
  end

  def get_copy_data # rubocop:disable Naming/AccessorMethodName
    @messages.shift
  end

  def put_copy_data(payload)
    @sent << payload
  end
end

class StreamTest < Minitest::Test
  def config(feedback_interval: 1000.0)
    Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: ["pub1"],
      feedback_interval:
    )
  end

  def test_yields_xlog_payload
    payload = "pgoutput".b
    copy_data = "w".b + [1, 2, 3].pack("Q>Q>Q>") + payload
    connection = FakeConnection.new([copy_data])
    stream = Pgoutput::Client::Stream.new(connection:, configuration: config)
    yielded = []

    stream.define_singleton_method(:start) do |&block|
      copy_data = connection.get_copy_data
      send(:process_copy_data, copy_data, &block)
    end

    stream.start { |pgoutput, metadata| yielded << [pgoutput, metadata.wal_end] }

    assert_equal [[payload, 2]], yielded
  end

  def test_sends_feedback_on_keepalive_request
    copy_data = "k".b + [10, 20].pack("Q>Q>") + [1].pack("C")
    connection = FakeConnection.new([copy_data])
    stream = Pgoutput::Client::Stream.new(connection:, configuration: config)

    stream.define_singleton_method(:start) do
      copy_data = connection.get_copy_data
      send(:process_copy_data, copy_data) { |_payload, _metadata| }
    end

    stream.start

    assert_equal 1, connection.sent.size
    assert_equal "r".ord, connection.sent.first.getbyte(0)
  end

  def test_rejects_unknown_message_type
    connection = FakeConnection.new(["?".b])
    stream = Pgoutput::Client::Stream.new(connection:, configuration: config)

    assert_raises(Pgoutput::Client::ProtocolError) do
      stream.send(:process_copy_data, connection.get_copy_data) { |_payload, _metadata| }
    end
  end
end
