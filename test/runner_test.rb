# frozen_string_literal: true

require "test_helper"

class RunnerTest < Minitest::Test
  def test_requires_block
    runner = Pgoutput::Client::Runner.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: ["pub1"]
    )

    assert_raises(ArgumentError) { runner.start }
  end

  def test_stop_is_available
    runner = Pgoutput::Client::Runner.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: ["pub1"]
    )

    assert_nil runner.stop
  end
end
