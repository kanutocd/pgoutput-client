# frozen_string_literal: true

require "test_helper"

class LSNTest < Minitest::Test
  def test_parse_lsn
    assert_equal 23_817_296, Pgoutput::Client::LSN.parse("0/16B6C50")
  end

  def test_format_lsn
    assert_equal "0/16B6C50", Pgoutput::Client::LSN.format(23_817_296)
  end

  def test_round_trip_high_segment
    integer = Pgoutput::Client::LSN.parse("1/FFFFFFFF")

    assert_equal "1/FFFFFFFF", Pgoutput::Client::LSN.format(integer)
  end

  def test_rejects_invalid_lsn
    assert_raises(ArgumentError) { Pgoutput::Client::LSN.parse("not-lsn") }
  end

  def test_rejects_negative_format
    assert_raises(ArgumentError) { Pgoutput::Client::LSN.format(-1) }
  end
end
