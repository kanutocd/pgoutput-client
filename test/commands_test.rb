# frozen_string_literal: true

require "test_helper"

class CommandsTest < Minitest::Test
  def setup
    @config = Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: %w[pub1 pub2],
      start_lsn: "0/10",
      binary: true,
      messages: true
    )
  end

  def test_configuration_boolean_defaults_are_false
    config = Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: %w[pub1 pub2]
    )

    refute config.binary
    refute config.messages
    refute config.auto_create_slot
    refute config.temporary_slot
  end

  def test_create_replication_slot
    assert_equal(
      "CREATE_REPLICATION_SLOT slot1 LOGICAL pgoutput",
      Pgoutput::Client::Commands.create_replication_slot(@config)
    )
  end

  def test_temporary_create_replication_slot
    config = Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: ["pub1"],
      temporary_slot: true
    )

    assert_equal(
      "CREATE_REPLICATION_SLOT slot1 TEMPORARY LOGICAL pgoutput",
      Pgoutput::Client::Commands.create_replication_slot(config)
    )
  end

  def test_drop_replication_slot
    assert_equal "DROP_REPLICATION_SLOT slot1", Pgoutput::Client::Commands.drop_replication_slot(@config)
  end

  def test_start_replication
    assert_equal(
      %(START_REPLICATION SLOT slot1 LOGICAL 0/10 ("proto_version" '1', "publication_names" 'pub1,pub2', "binary" 'true', "messages" 'true')), # rubocop:disable Layout/LineLength
      Pgoutput::Client::Commands.start_replication(@config)
    )
  end
end
