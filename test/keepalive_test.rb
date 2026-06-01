# frozen_string_literal: true

require "test_helper"

class KeepaliveTest < Minitest::Test
  def test_parses_keepalive
    bytes = "k".b + [100, 200].pack("Q>Q>") + [1].pack("C")

    message = Pgoutput::Client::Keepalive.parse(bytes)

    assert_equal 100, message.wal_end
    assert_equal 200, message.server_clock
    assert message.reply_requested
    assert_equal "0/64", message.wal_end_lsn
    assert Ractor.shareable?(message)
  end

  def test_reply_requested_false
    bytes = "k".b + [100, 200].pack("Q>Q>") + [0].pack("C")

    refute Pgoutput::Client::Keepalive.parse(bytes).reply_requested
  end

  def test_rejects_non_keepalive
    assert_raises(Pgoutput::Client::ProtocolError) do
      Pgoutput::Client::Keepalive.parse("w".b + "\0".b * 24)
    end
  end
end
