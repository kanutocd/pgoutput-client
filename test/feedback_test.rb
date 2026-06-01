# frozen_string_literal: true

require_relative "test_helper"

class FeedbackTest < Minitest::Test
  def test_now_uses_defaults_and_current_clock
    Pgoutput::Client::Feedback.stub(:current_pg_time, 123) do
      feedback = Pgoutput::Client::Feedback.now(received_lsn: 0x10)

      assert_equal 0x10, feedback.received_lsn
      assert_equal 0x10, feedback.flushed_lsn
      assert_equal 0x10, feedback.applied_lsn
      assert_equal 123, feedback.client_clock
      refute feedback.reply_requested
    end
  end

  def test_now_accepts_explicit_values
    Pgoutput::Client::Feedback.stub(:current_pg_time, 456) do
      feedback = Pgoutput::Client::Feedback.now(
        received_lsn: 0x10,
        flushed_lsn: 0x20,
        applied_lsn: 0x30,
        reply_requested: true
      )

      assert_equal [0x10, 0x20, 0x30, 456, true], [
        feedback.received_lsn,
        feedback.flushed_lsn,
        feedback.applied_lsn,
        feedback.client_clock,
        feedback.reply_requested
      ]
    end
  end

  def test_to_copy_data_without_reply_request
    feedback = Pgoutput::Client::Feedback.new(1, 2, 3, 4, false)

    assert_equal "r".b + [1, 2, 3, 4].pack("Q>Q>Q>Q>") + "\0".b, feedback.to_copy_data
    assert feedback.to_copy_data.frozen?
  end

  def test_to_copy_data_with_reply_request
    feedback = Pgoutput::Client::Feedback.new(1, 2, 3, 4, true)

    assert_equal 1, feedback.to_copy_data.getbyte(-1)
  end

  def test_current_pg_time_returns_integer
    assert_kind_of Integer, Pgoutput::Client::Feedback.current_pg_time
  end
end
