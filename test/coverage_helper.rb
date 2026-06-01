# frozen_string_literal: true

return unless ENV["COVERAGE"] == "true"

require "simplecov"

SimpleCov.command_name "Minitest"

SimpleCov.start do
  enable_coverage :branch
  track_files "lib/**/*.rb"
  add_filter "/test/"
  # minimum_coverage line: 90
  # minimum_coverage branch: 90
end
