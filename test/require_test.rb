# frozen_string_literal: true

require_relative "test_helper"

class RequireTest < Minitest::Test
  def test_version_is_defined
    assert_match(/\A\d+\.\d+\.\d+\z/, Pgoutput::Client::VERSION)
  end

  def test_error_hierarchy
    assert_operator Pgoutput::Client::ConfigurationError, :<, Pgoutput::Client::Error
    assert_operator Pgoutput::Client::ProtocolError, :<, Pgoutput::Client::Error
    assert_operator Pgoutput::Client::ConnectionError, :<, Pgoutput::Client::Error
  end
end
