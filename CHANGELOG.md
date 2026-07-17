# Changelog

## Unreleased

## 0.4.0 - 2026-07-17

### Added

- Added `SlotStatus#retained_wal_bytes`, computed by PostgreSQL from the current
  WAL position and the slot's `restart_lsn`.

## 0.3.0 - 2026-07-17

### Added

- Added `Runner#slot_status` and `SlotInspector` for version-tolerant
  `pg_replication_slots` inspection.
- Added immutable `SlotStatus` snapshots exposing transport and slot-health
  fields without imposing downstream recovery policy.

## 0.2.4 - 2026-06-17

### Added

- Added socket-aware replication stream polling.
- Added E2E coverage for PostgreSQL restart and replication stream recovery.
- Added connection readiness checks to E2E infrastructure.

### Changed

- Improved replication stream handling during idle periods.
- Improved reconnect behavior after PostgreSQL restarts.
- Improved standby feedback reliability during long-running streams.
- Improved E2E test stability across PostgreSQL startup and restart scenarios.
- Normalized `PG#get_copy_data` idle responses to simplify stream processing.

### Fixed

- Fixed replication stream recovery after PostgreSQL restart.
- Fixed handling of idle COPY stream reads.
- Fixed reconnect loops triggered by PostgreSQL replication timeouts.
- Fixed E2E race conditions during PostgreSQL initialization.
- Fixed replication slot creation behavior when a slot already exists.
- Fixed several edge cases uncovered by Mammoth integration testing.

### Documentation

- Expanded YARD documentation coverage to 98.95%.

## 0.2.3 - 2026-06-17

### Fixed

* Fixed automatic replication slot creation when `auto_create_slot` is enabled.
* Fixed startup failure when the configured replication slot already exists.
* Improved logical replication restart behavior for persistent replication slots.
* Improved lifecycle management of existing replication slots across process and container restarts.

### Changed

* `auto_create_slot` now follows **ensure slot exists** semantics.
* Existing replication slots are treated as valid and reusable when automatic slot creation is enabled.
* Slot creation remains automatic for missing slots and idempotent for existing slots.

### Internal

* Hardened replication slot lifecycle handling.
* Expanded coverage around automatic slot creation scenarios.
* Updated signatures and tests for slot creation behavior.


## 0.2.2 - 2026-06-17

### Added

* Added periodic standby status feedback while replication streams are idle.
* Added E2E coverage for PostgreSQL restart and replication recovery.
* Added E2E validation of replication slot resume behavior after reconnect.
* Added test coverage for idle replication streams.

### Changed

* Increased reconnect retry budget to better tolerate PostgreSQL restart windows.
* Improved replication stream resilience during transient PostgreSQL outages.
* Improved reconnect behavior when PostgreSQL is starting up and temporarily rejecting connections.

### Fixed

* Fixed replication timeout during idle logical replication streams.

* Fixed walsender termination caused by missing standby feedback during periods without WAL activity.

* Fixed reconnect handling after PostgreSQL restart.

* Fixed connection recovery when PostgreSQL reports:

  ```
  FATAL: the database system is starting up
  ```

* Fixed E2E PostgreSQL test infrastructure and restart recovery validation.

* Fixed test isolation between unit and E2E PostgreSQL connection paths.

### Internal

* Expanded transport lifecycle validation.
* Improved operational reliability of long-running replication sessions.


## [0.2.1] - 2026-06-16

- Gemspec summary and description improvement release only

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
