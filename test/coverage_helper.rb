# frozen_string_literal: true

if ENV.fetch("COVERAGE", "false").to_s == "true"
  require "simplecov"

  SimpleCov.start do
    enable_coverage :branch
    add_filter "/test/"
    add_filter "/sig/"
  end  
end

