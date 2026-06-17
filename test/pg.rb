# frozen_string_literal: true

module PG
  class << self
    attr_accessor :connect_result, :connect_error, :last_connect_args
  end
end

if ENV["PGOUTPUT_CLIENT_E2E"] == "1"
  spec = Gem::Specification.find_by_name("pg")
  load File.join(spec.full_gem_path, "lib", "pg.rb")

  module PG
    class << self
      alias __pgoutput_client_real_connect connect unless respond_to?(:__pgoutput_client_real_connect)

      def connect(database_url, replication: nil)
        self.last_connect_args = [database_url, replication]
        raise connect_error if connect_error
        return connect_result unless connect_result.nil?

        if replication
          __pgoutput_client_real_connect(database_url, replication: replication)
        else
          __pgoutput_client_real_connect(database_url)
        end
      end
    end
  end
else
  module PG
    class Error < StandardError; end

    def self.connect(database_url, replication: nil)
      self.last_connect_args = [database_url, replication]
      raise connect_error if connect_error

      connect_result
    end
  end
end
