# frozen_string_literal: true

module PG
  class Error < StandardError; end

  class << self
    attr_accessor :connect_result, :connect_error, :last_connect_args
  end

  def self.connect(database_url, replication:)
    self.last_connect_args = [database_url, replication]
    raise connect_error if connect_error

    connect_result
  end
end
