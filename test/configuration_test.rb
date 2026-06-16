# frozen_string_literal: true

require_relative "test_helper"

class ConfigurationTest < Minitest::Test
  def build(**overrides)
    Pgoutput::Client::Configuration.new(
      database_url: "postgres://localhost/app",
      slot_name: "slot1",
      publication_names: "pub1",
      **overrides
    )
  end

  def test_defaults_are_frozen_and_boolean_false
    configuration = build

    assert configuration.frozen?
    assert_equal "postgres://localhost/app", configuration.database_url
    assert_equal "slot1", configuration.slot_name
    assert_equal ["pub1"], configuration.publication_names
    assert_nil configuration.start_lsn
    assert_equal "0/0", configuration.start_lsn_string
    assert_equal 1, configuration.proto_version
    refute configuration.binary
    refute configuration.messages
    refute configuration.auto_create_slot
    refute configuration.temporary_slot
    assert_equal 10.0, configuration.feedback_interval
  end

  def test_accepts_array_publication_names_and_integer_lsn
    configuration = build(publication_names: %w[pub1 pub2], start_lsn: 0x10)

    assert_equal %w[pub1 pub2], configuration.publication_names
    assert_equal "0/10", configuration.start_lsn
    assert_equal "0/10", configuration.start_lsn_string
  end

  def test_accepts_string_lsn_and_custom_values
    configuration = build(
      start_lsn: "1/2",
      proto_version: "2",
      binary: true,
      messages: true,
      auto_create_slot: true,
      temporary_slot: true,
      feedback_interval: "0.25"
    )

    assert_equal "1/2", configuration.start_lsn
    assert_equal 2, configuration.proto_version
    assert configuration.binary
    assert configuration.messages
    assert configuration.auto_create_slot
    assert configuration.temporary_slot
    assert_equal 0.25, configuration.feedback_interval
  end

  def test_rejects_empty_publication_names
    error = assert_raises(Pgoutput::Client::ConfigurationError) do
      build(publication_names: [])
    end

    assert_equal "publication_names must not be empty", error.message
  end

  def test_rejects_invalid_slot_name
    error = assert_raises(Pgoutput::Client::ConfigurationError) do
      build(slot_name: "bad-name")
    end

    assert_equal "slot_name must be a PostgreSQL identifier-like string", error.message
  end

  def test_rejects_invalid_publication_name
    error = assert_raises(Pgoutput::Client::ConfigurationError) do
      build(publication_names: %w[pub1 bad-name])
    end

    assert_equal "publication_name must be a PostgreSQL identifier-like string", error.message
  end

  def test_rejects_plugin_keyword
    error = assert_raises(ArgumentError) do
      build(plugin: "pgoutput")
    end

    assert_match(/unknown keyword: :plugin/, error.message)
  end

  def test_rejects_non_positive_proto_version
    error = assert_raises(Pgoutput::Client::ConfigurationError) do
      build(proto_version: 0)
    end

    assert_equal "proto_version must be positive", error.message
  end

  def test_rejects_non_positive_feedback_interval
    error = assert_raises(Pgoutput::Client::ConfigurationError) do
      build(feedback_interval: 0)
    end

    assert_equal "feedback_interval must be positive", error.message
  end

  def test_rejects_invalid_lsn
    assert_raises(ArgumentError) { build(start_lsn: "not-an-lsn") }
  end
end
