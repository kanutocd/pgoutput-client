# frozen_string_literal: true

require_relative "lib/pgoutput/client/version"

Gem::Specification.new do |spec|
  spec.name = "pgoutput-client"
  spec.version = Pgoutput::Client::VERSION
  spec.authors = ["Ken C. Demanawa"]
  spec.email = ["kenneth.c.demanawa@gmail.com"]

  spec.summary = "PostgreSQL pgoutput logical replication transport client."
  spec.description = "Transport-only PostgreSQL logical replication client for receiving pgoutput CopyData payloads."
  spec.homepage = "https://kanutocd.github.io/pgoutput-client/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kanutocd/pgoutput-client"
  spec.metadata["changelog_uri"] = "#{spec.metadata["source_code_uri"]}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "examples/**/*.rb",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "pg", "~> 1.6"
end
