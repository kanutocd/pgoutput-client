# frozen_string_literal: true

require "test_helper"

class XLogDataTest < Minitest::Test
  def test_parses_xlog_data
    payload = "BINARY-PGOUTPUT".b
    bytes = "w".b + [10, 20, 30].pack("Q>Q>Q>") + payload

    message = Pgoutput::Client::XLogData.parse(bytes)

    assert_equal 10, message.wal_start
    assert_equal 20, message.wal_end
    assert_equal 30, message.server_clock
    assert_equal payload, message.payload
    assert_equal "0/A", message.wal_start_lsn
    assert_equal "0/14", message.wal_end_lsn
    assert Ractor.shareable?(message)
  end

  def test_rejects_non_xlog_data
    assert_raises(Pgoutput::Client::ProtocolError) do
      Pgoutput::Client::XLogData.parse("k".b + "\0".b * 17)
    end
  end

  def test_rejects_truncated_xlog_data
    assert_raises(Pgoutput::Client::ProtocolError) do
      Pgoutput::Client::XLogData.parse("w".b)
    end
  end
end
