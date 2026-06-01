# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### Added

- Placeholder for future development.

---

## [0.1.0] - 2026-05-31

### Added

- Initial transport-only PostgreSQL logical replication client.
- Added `Pgoutput::Client::Runner` facade.
- Added immutable configuration object.
- Added LSN parse and format helpers.
- Added XLogData envelope parsing.
- Added primary keepalive parsing.
- Added standby feedback payload builder.
- Added replication command builders.
- Added `PG::Connection` wrapper.
- Added logical replication stream loop.
- Added RBS signatures.
- Added Minitest test suite.
- Added README and examples.

### Notes

This release intentionally does not parse pgoutput protocol messages or decode PostgreSQL values.
