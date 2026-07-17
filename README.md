# pgoutput-client

[![Gem Version](https://badge.fury.io/rb/pgoutput-client.svg)](https://badge.fury.io/rb/pgoutput-client)
[![CI](https://github.com/kanutocd/pgoutput-client/workflows/CI/badge.svg)](https://github.com/kanutocd/pgoutput-client/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%203.4-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)


A transport-only PostgreSQL logical replication client for receiving raw `pgoutput` payloads in Ruby.

`pgoutput-client` connects to PostgreSQL using logical replication, starts a `pgoutput` replication stream, receives `CopyData` messages, handles keepalives, sends standby feedback, and yields raw pgoutput payload bytes to downstream gems such as `pgoutput-parser` and `pgoutput-decoder`.

It intentionally does **not** parse row-change messages or decode PostgreSQL values.

---

## Requirements

- Ruby 3.4+
- PostgreSQL 10+
- `pg` gem
- PostgreSQL publication and logical replication slot

---

## Ecosystem Position

```text
PostgreSQL logical replication
        │
        ▼
pgoutput-client
        │
        ▼
CopyData / pgoutput payloads
        │
        ▼
pgoutput-parser
        │
        ▼
Protocol messages
        │
        ▼
pgoutput-decoder
        │
        ▼
Decoded row events
```

`pgoutput-client` is the transport layer only.

---

## Features

- Opens PostgreSQL logical replication connections
- Builds replication commands
- Supports `CREATE_REPLICATION_SLOT`
- Supports `DROP_REPLICATION_SLOT`
- Supports `START_REPLICATION SLOT ... LOGICAL ...`
- Inspects version-dependent `pg_replication_slots` state
- Parses XLogData envelopes
- Parses primary keepalive messages
- Builds standby feedback messages
- Provides LSN parse/format helpers
- Yields raw pgoutput payload bytes
- Includes RBS signatures
- Includes Minitest coverage
- No audit, parser, or decoder concerns

---

## Installation

```ruby
gem "pgoutput-client"
```

Then:

```bash
bundle install
```

Require:

```ruby
require "pgoutput-client"
```

---

## Quick Start

```ruby
require "pgoutput-client"

client =
  Pgoutput::Client::Runner.new(
    database_url: ENV.fetch("DATABASE_URL"),
    slot_name: "my_slot",
    publication_names: ["my_publication"],
    auto_create_slot: true
  )

client.start do |payload, metadata|
  puts "WAL end: #{metadata.wal_end_lsn}"
  puts "Raw pgoutput payload bytes: #{payload.bytesize}"
end
```

---

## Using With pgoutput-parser

```ruby
require "pgoutput-client"
require "pgoutput"

client = Pgoutput::Client::Runner.new(
  database_url: ENV.fetch("DATABASE_URL"),
  slot_name: "my_slot",
  publication_names: ["my_publication"]
)

tracker = Pgoutput::RelationTracker.new

client.start do |payload, metadata|
  message = tracker.process(payload)
  p [metadata.wal_end_lsn, message]
end
```

---

## Using With pgoutput-decoder

```ruby
require "pgoutput-client"
require "pgoutput"
require "pgoutput/decoder"

tracker = Pgoutput::RelationTracker.new
decoder = Pgoutput::Decoder.new

client.start do |payload, metadata|
  protocol_message = tracker.process(payload)
  event = decoder.decode(protocol_message)
  p [metadata.wal_end_lsn, event]
end
```

---

## What This Gem Does

```text
PostgreSQL replication connection
        │
        ▼
CopyData stream
        │
        ▼
XLogData / Keepalive handling
        │
        ▼
Raw pgoutput payloads
```

It owns:

- Replication connection setup
- Replication command generation
- CopyData reading
- XLogData envelope parsing
- Keepalive handling
- Standby status feedback
- LSN conversion
- Replication-slot catalog inspection

---

## What This Gem Does Not Do

It does not:

- Parse pgoutput row messages
- Decode PostgreSQL OIDs
- Build application events
- Group transactions
- Run processor pipelines
- Manage Ractor worker pools
- Store audit records
- Own replay, checkpointing, deduplication, or sink ordering

Those responsibilities belong to higher layers, especially `cdc-core` and the sink that materializes downstream state.

## Failure Semantics

If the live replication stream loses its connection, `pgoutput-client` retries a small number of times with a backoff and resumes from the latest confirmed WAL position.

It does not decide replay policy, deduplication strategy, checkpoint storage, or exactly-once delivery. Those concerns belong to the downstream CDC runtime and sink layer.

---

## Logical Replication Setup

Example PostgreSQL setup:

```sql
ALTER SYSTEM SET wal_level = logical;

CREATE PUBLICATION my_publication FOR TABLE users, posts;
```

Create a slot automatically:

```ruby
Pgoutput::Client::Runner.new(
  database_url: ENV.fetch("DATABASE_URL"),
  slot_name: "my_slot",
  publication_names: ["my_publication"],
  auto_create_slot: true
)
```

Or create the slot yourself:

```sql
SELECT * FROM pg_create_logical_replication_slot('my_slot', 'pgoutput');
```

---

## Public API

### Pgoutput::Client::Runner

High-level facade.

```ruby
client = Pgoutput::Client::Runner.new(...)
client.start { |payload, metadata| ... }
```

Inspect the configured replication slot before applying a downstream recovery
policy:

```ruby
status = client.slot_status

if status.nil?
  warn "replication slot is missing"
else
  puts status.restart_lsn
  puts status.confirmed_flush_lsn
  puts status.retained_wal_bytes
  puts status.wal_status
  puts status.invalidation_reason
end
```

`SlotStatus` reflects the fields available on the connected PostgreSQL version.
Optional fields are `nil` on versions that do not expose them. The client
reports catalog state only; deciding whether a durable checkpoint is safe to
resume remains the downstream runtime's responsibility.

### Pgoutput::Client::SlotInspector

Queries `pg_replication_slots` through a short-lived ordinary PostgreSQL
connection. `#fetch(slot_name)` returns `nil` when the slot is missing and a
`SlotStatus` snapshot otherwise. `Runner#slot_status` is the convenient entry
point for inspecting the runner's configured slot.

### Pgoutput::Client::SlotStatus

Immutable replication-slot catalog snapshot. It exposes identity, activity,
WAL position, retention, and invalidation fields including:

- `slot_name`, `plugin`, `slot_type`, and `database`
- `active`, `active_pid`, and `inactive_since`
- `restart_lsn`, `confirmed_flush_lsn`, and `retained_wal_bytes`
- `wal_status`, `safe_wal_size`, and `catalog_xmin`
- `conflicting` and `invalidation_reason`

### Pgoutput::Client::Configuration

Immutable configuration object.

### Pgoutput::Client::Connection

Thin wrapper around `PG::Connection` for replication commands.

### Pgoutput::Client::Stream

Consumes CopyData messages and yields pgoutput payloads.

### Pgoutput::Client::LSN

```ruby
Pgoutput::Client::LSN.parse("0/16B6C50")
Pgoutput::Client::LSN.format(23_817_296)
```

### Pgoutput::Client::XLogData

Represents a WAL data envelope.

### Pgoutput::Client::Keepalive

Represents a primary keepalive message.

### Pgoutput::Client::Feedback

Builds standby status update payloads.

---

## Ractor Position

The replication connection itself is stateful and ordered. It should normally run as a single reader.

Downstream parsing, decoding, and processing can be parallelized with Ractors:

```text
pgoutput-client reader
        │
        ▼
Ractor-safe queue
        │
        ▼
parser / decoder / processor pools
```

---

## Rake Tasks

### Default

Run them all

```bash
bundle exec rake
```

### Code Linting and Formatting

```bash
bundle exec rake rubocop
```

### Testing

```bash
bundle exec rake test
```

With coverage:

```bash
COVERAGE=true bundle exec rake test
```
---

### Type Checking

```bash
bundle exec rbs:validate
```

---

### Documentation

```bash
bundle exec rake yard
```

### End-to-End PostgreSQL

Run the full Docker-backed E2E flow and clean up afterward:

```bash
script/test-e2e
```

Keep PostgreSQL running after the test for debugging:

```bash
KEEP_E2E_POSTGRES=1 script/test-e2e
```

You can also run the steps manually:

```bash
script/e2e-up
PGOUTPUT_CLIENT_E2E=1 bundle exec rake test:e2e
script/e2e-down
```

Equivalent Rake task:

```bash
bundle exec rake e2e:run
```

## Transport lifecycle behavior

`pgoutput-client` owns PostgreSQL logical replication transport and lifecycle
management. It opens the replication connection, optionally creates the logical
replication slot, starts streaming, sends standby status feedback, and retries
reconnectable failures.

### Idle standby feedback

Long-running replication streams can be quiet for long periods when no WAL
changes are produced. During those idle periods the client wakes periodically
and sends standby status feedback so PostgreSQL does not terminate the walsender
for replication timeout.

Control the feedback cadence with `feedback_interval`:

```ruby
runner = Pgoutput::Client::Runner.new(
  database_url: ENV.fetch("DATABASE_URL"),
  slot_name: "mammoth_live",
  publication_names: ["mammoth_publication"],
  feedback_interval: 10.0
)
```

### Idempotent automatic slot creation

When `auto_create_slot` is enabled, the client treats slot creation as
"ensure this slot exists". Missing slots are created before streaming; existing
slots are reused and do not cause startup failure.

```ruby
runner = Pgoutput::Client::Runner.new(
  database_url: ENV.fetch("DATABASE_URL"),
  slot_name: "mammoth_live",
  publication_names: ["mammoth_publication"],
  auto_create_slot: true,
  temporary_slot: false
)
```

Existence alone does not prove that an existing or newly created slot can serve
a downstream durable checkpoint. Use `Runner#slot_status` to obtain catalog
state and apply continuity or recovery policy in the downstream runtime before
streaming.

Publication creation remains outside this gem. Create publications through
application migrations, database bootstrap SQL, or infrastructure tooling.

### Restart recovery

After a stream has connected successfully, transient PostgreSQL outages are
retried through the reconnect lifecycle. This includes ordinary container or
process restart windows where PostgreSQL temporarily refuses connections or
reports that the database system is starting up.

---

## License

[MIT](LICENSE.txt).
