# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def test_valid_configuration
    config = Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: ["pub1"],
      start_lsn: "0/16B6C50"
    )

    assert_equal "postgres://localhost/app", config.database_url
    assert_equal "slot1", config.slot_name
    assert_equal ["pub1"], config.publication_names
    assert_equal "0/16B6C50", config.start_lsn
    assert config.frozen?
  end

  def test_accepts_integer_start_lsn
    config = Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: "pub1",
      start_lsn: 10
    )

    assert_equal "0/A", config.start_lsn
  end

  def test_rejects_bad_identifier
    assert_raises(Pgoutput::Client::ConfigurationError) do
      Pgoutput::Client::Configuration.new(
        database_url: "postgres://localhost/app",
        slot_name: "bad-slot",
        publication_names: ["pub1"]
      )
    end
  end

  def test_strict_boolean_arguments
    args = { database_url: "postgres://localhost/app",
             slot_name: "slot1",
             publication_names: "pub1",
             start_lsn: 10 }
    needs_boolean = { binary: nil, messages: "", auto_create_slot: 0, temporary_slot: nil }
    needs_boolean.each_pair do |k, v|
      assert_raises(ArgumentError) do
        Pgoutput::Client::Configuration.new(args.merge(k => v))
      end
      assert Pgoutput::Client::Configuration.new(**args.merge(k => [true, false][rand(2)])).frozen?
    end
  end

  def test_rejects_empty_publications
    assert_raises(Pgoutput::Client::ConfigurationError) do
      Pgoutput::Client::Configuration.new(
        database_url: "postgres://localhost/app",
        slot_name: "slot1",
        publication_names: []
      )
    end
  end
end
