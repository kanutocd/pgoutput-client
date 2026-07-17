# frozen_string_literal: true

require_relative "test_helper"

class XLogDataTest < Minitest::Test
  def payload(wal_start: 0x10, wal_end: 0x20, server_clock: 0x30, body: "abc")
    "w".b + [wal_start, wal_end, server_clock].pack("Q>Q>Q>") + body.b
  end

  def test_parse_xlog_data
    xlog = Pgoutput::Client::XLogData.parse(payload)

    assert_equal 0x10, xlog.wal_start
    assert_equal 0x20, xlog.wal_end
    assert_equal 0x30, xlog.server_clock
    assert_equal "abc", xlog.payload
    assert_equal "0/10", xlog.wal_start_lsn
    assert_equal "0/20", xlog.wal_end_lsn
    assert_predicate xlog, :frozen?
    assert_predicate xlog.payload, :frozen?
  end

  def test_parse_xlog_data_without_payload_body
    assert_equal "", Pgoutput::Client::XLogData.parse(payload(body: "")).payload
  end

  def test_parse_rejects_empty_payload
    error = assert_raises(Pgoutput::Client::ProtocolError) { Pgoutput::Client::XLogData.parse("") }
    assert_equal "empty CopyData payload", error.message
  end

  def test_parse_rejects_wrong_message_type
    error = assert_raises(Pgoutput::Client::ProtocolError) { Pgoutput::Client::XLogData.parse("k#{"\0" * 24}") }
    assert_equal "expected XLogData message", error.message
  end

  def test_parse_rejects_truncated_payload
    error = assert_raises(Pgoutput::Client::ProtocolError) { Pgoutput::Client::XLogData.parse("w#{"\0" * 23}") }
    assert_equal "truncated XLogData message", error.message
  end

  def test_unpack_u64_rejects_offset_beyond_buffer
    assert_raises(Pgoutput::Client::ProtocolError) do
      Pgoutput::Client::XLogData.send(
        :unpack_u64,
        "\x00" * 8,
        100
      )
    end
  end

  def test_unpack_u64_rejects_truncated_8byte_field
    assert_raises(Pgoutput::Client::ProtocolError) do
      Pgoutput::Client::XLogData.send(
        :unpack_u64,
        "\x00" * 7,
        0
      )
    end
  end
end
