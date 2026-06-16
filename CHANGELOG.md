# Changelog

## Unreleased

## [0.2.0] - 2026-06-16

### Fixed

- Remove the configurable plugin surface; this transport layer is fixed to `pgoutput`.
- Wire `Pgoutput::Client::Runner#stop` to the active stream for cooperative shutdown.
- Back off briefly when the replication socket has no `CopyData` ready instead of busy polling.
- Retry live stream connection loss with backoff and resume from the latest confirmed WAL position.
- Avoid recreating an existing replication slot during reconnect attempts.
- Document the Docker-backed E2E workflow in the README and test skip hint.
- Document that replay, checkpointing, deduplication, and sink ordering belong to downstream layers.
- Add a live E2E reconnect test that restarts PostgreSQL mid-stream and verifies resume behavior.

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
