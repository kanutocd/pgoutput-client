# pgoutput-client

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

Those responsibilities belong to higher layers.

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

## Testing

```bash
bundle exec rake test
```

With coverage:

```bash
COVERAGE=true bundle exec rake test
```

---

## Type Checking

```bash
bundle exec steep check
```

---

## Documentation

```bash
bundle exec yard doc
```

---

## License

MIT.
