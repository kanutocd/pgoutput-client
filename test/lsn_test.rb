# frozen_string_literal: true

require_relative "test_helper"

class LSNTest < Minitest::Test
  def test_parse_and_format
    assert_equal 0x0000_0001_0000_0002, Pgoutput::Client::LSN.parse("1/2")
    assert_equal "1/2", Pgoutput::Client::LSN.format(0x0000_0001_0000_0002)
  end

  def test_parse_rejects_missing_separator
    error = assert_raises(ArgumentError) { Pgoutput::Client::LSN.parse("12") }
    assert_equal 'invalid LSN: "12"', error.message
  end

  def test_parse_rejects_invalid_hex
    error = assert_raises(ArgumentError) { Pgoutput::Client::LSN.parse("G/1") }
    assert_equal 'invalid LSN: "G/1"', error.message
  end

  def test_format_rejects_negative_value
    error = assert_raises(ArgumentError) { Pgoutput::Client::LSN.format(-1) }
    assert_equal "LSN must be non-negative", error.message
  end
end
