# frozen_string_literal: true

require "test_helper"

class FeedbackTest < Minitest::Test
  def test_builds_feedback_payload
    feedback = Pgoutput::Client::Feedback.new(1, 2, 3, 4, true)
    payload = feedback.to_copy_data

    assert_equal "r".ord, payload.getbyte(0)
    assert_equal [1, 2, 3, 4], payload.byteslice(1, 32).unpack("Q>Q>Q>Q>")
    assert_equal 1, payload.getbyte(33)
    assert payload.frozen?
  end

  def test_now_uses_received_lsn_defaults
    feedback = Pgoutput::Client::Feedback.now(received_lsn: 42)

    assert_equal 42, feedback.received_lsn
    assert_equal 42, feedback.flushed_lsn
    assert_equal 42, feedback.applied_lsn
    assert_instance_of Integer, feedback.client_clock
  end
end
