# frozen_string_literal: true

require_relative "test_helper"

class KeepaliveTest < Minitest::Test
  def payload(wal_end: 0x20, server_clock: 0x30, reply_requested: false)
    "k".b + [wal_end, server_clock].pack("Q>Q>") + [reply_requested ? 1 : 0].pack("C")
  end

  def test_parse_keepalive_without_reply_request
    keepalive = Pgoutput::Client::Keepalive.parse(payload)

    assert_equal 0x20, keepalive.wal_end
    assert_equal 0x30, keepalive.server_clock
    refute keepalive.reply_requested
    assert_equal "0/20", keepalive.wal_end_lsn
    assert_predicate keepalive, :frozen?
  end

  def test_parse_keepalive_with_reply_request
    assert Pgoutput::Client::Keepalive.parse(payload(reply_requested: true)).reply_requested
  end

  def test_parse_rejects_empty_payload
    error = assert_raises(Pgoutput::Client::ProtocolError) { Pgoutput::Client::Keepalive.parse("") }
    assert_equal "empty CopyData payload", error.message
  end

  def test_parse_rejects_wrong_message_type
    error = assert_raises(Pgoutput::Client::ProtocolError) { Pgoutput::Client::Keepalive.parse("w#{"\0" * 17}") }
    assert_equal "expected keepalive message", error.message
  end

  def test_parse_rejects_truncated_payload
    error = assert_raises(Pgoutput::Client::ProtocolError) { Pgoutput::Client::Keepalive.parse("k#{"\0" * 16}") }
    assert_equal "truncated keepalive message", error.message
  end

  def test_unpack_u64_rejects_offset_beyond_buffer
    assert_raises(Pgoutput::Client::ProtocolError) do
      Pgoutput::Client::Keepalive.send(
        :unpack_u64,
        "\x00" * 8,
        100
      )
    end
  end

  def test_unpack_u64_rejects_truncated_8byte_field
    assert_raises(Pgoutput::Client::ProtocolError) do
      Pgoutput::Client::Keepalive.send(
        :unpack_u64,
        "\x00" * 7,
        0
      )
    end
  end
end
