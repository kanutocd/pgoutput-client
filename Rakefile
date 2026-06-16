# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"
require "yard"

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--parallel"]
end

desc "Run tests"
task :test do
  test_files = Dir["test/**/*_test.rb"].map { |file| "require_relative #{file.inspect}" }.join("; ")

  sh [
    RbConfig.ruby,
    "-r./test/coverage_helper",
    "-Ilib:test",
    "-w",
    "-e",
    test_files.inspect
  ].join(" ")
end

# so both `bundle exec rake yard` and `bundle exec yard doc` fetches options from ./.yardopts
YARD::Rake::YardocTask.new(:yard)

task default: %i[test rubocop yard]

namespace :rbs do
  desc "Generate RBS signatures"
  task :gen do
    sh "bundle exec rbs prototype rb --out-dir=sig --base-dir=lib lib"
  end

  desc "Validate RBS signatures"
  task :validate do
    sh "bundle exec steep check"
  end
end

namespace :test do
  desc "Run Docker PostgreSQL E2E tests"
  task :e2e do
    sh [
      RbConfig.ruby,
      "-Ilib",
      "-w",
      "test/e2e/postgres_logical_replication_test.rb"
    ].join(" ")
  end
end

namespace :e2e do
  desc "Start Docker PostgreSQL for E2E tests"
  task :up do
    sh "docker compose -f docker-compose.e2e.yml up -d"
  end

  desc "Wait for Docker PostgreSQL to accept E2E connections"
  task :wait do
    ruby = <<~RUBY
      require_relative "test/support/e2e_postgres"

      PgoutputClientE2E.wait_for_postgres!
    RUBY

    sh [
      RbConfig.ruby,
      "-Ilib:test",
      "-e",
      ruby.inspect
    ].join(" ")
  end

  desc "Stop Docker PostgreSQL for E2E tests"
  task :down do
    sh "docker compose -f docker-compose.e2e.yml down -v"
  end

  desc "Run E2E tests with Docker PostgreSQL and clean up afterward"
  task run: :up do
    Rake::Task["e2e:wait"].invoke
    sh({ "PGOUTPUT_CLIENT_E2E" => "1" }, "bundle exec rake test:e2e")
  ensure
    Rake::Task["e2e:down"].invoke unless ENV["KEEP_E2E_POSTGRES"] == "1"
  end
end
