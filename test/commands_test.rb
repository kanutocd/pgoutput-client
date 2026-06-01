# frozen_string_literal: true

require_relative "test_helper"

class CommandsTest < Minitest::Test
  def config(**overrides)
    Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: %w[pub1 pub2],
      start_lsn: "0/10",
      **overrides
    )
  end

  def test_create_replication_slot_without_temporary_default
    assert_equal(
      "CREATE_REPLICATION_SLOT slot1 LOGICAL pgoutput",
      Pgoutput::Client::Commands.create_replication_slot(config)
    )
  end

  def test_create_replication_slot_with_temporary_slot
    assert_equal(
      "CREATE_REPLICATION_SLOT slot1 TEMPORARY LOGICAL pgoutput",
      Pgoutput::Client::Commands.create_replication_slot(config(temporary_slot: true))
    )
  end

  def test_drop_replication_slot
    assert_equal "DROP_REPLICATION_SLOT slot1", Pgoutput::Client::Commands.drop_replication_slot(config)
  end

  def test_start_replication_with_required_options_only
    assert_equal(
      "START_REPLICATION SLOT slot1 LOGICAL 0/10 (\"proto_version\" '1', \"publication_names\" 'pub1,pub2')",
      Pgoutput::Client::Commands.start_replication(config)
    )
  end

  def test_start_replication_with_binary_and_messages
    assert_equal(
      "START_REPLICATION SLOT slot1 LOGICAL 0/10 (\"proto_version\" '1', \"publication_names\" 'pub1,pub2', \"binary\" 'true', \"messages\" 'true')", # rubocop:disable Layout/LineLength
      Pgoutput::Client::Commands.start_replication(config(binary: true, messages: true))
    )
  end
end
