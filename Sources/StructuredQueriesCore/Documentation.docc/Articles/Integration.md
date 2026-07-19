# Integrating with database libraries

Learn how to integrate this library into existing database libraries so that you can build queries
in a type-safe manner.

## Overview

Since this library focuses only on the building of type-safe queries, it does not come with a way to
actually execute the query in a particular database. The library is built with the goal of being
able to support any database (SQLite, MySQL, Postgres, _etc._), but currently is primarily tuned to
work with SQLite. And further, it only comes with one official driver for SQLite, which is the
[SQLiteData] library that uses the popular [GRDB] library under the hood for interacting with
SQLite.

If you are interested in building an integration of StructuredQueries with another database
library, please [start a discussion][sq-discussions] and let us know of any challenges you
encounter.

[SQLiteData]: http://github.com/pointfreeco/sqlite-data
[GRDB]: http://github.com/groue/GRDB.swift
[sq-discussions]: http://github.com/pointfreeco/swift-structured-queries/discussions/new/choose

### Case Study: SQLite

One can integrate StructuredQueries with the SQLite C library by taking a few small steps. One
first needs to define a conformance to the ``QueryDecoder`` protocol, which describes how to decode
certain database types into Swift types. And then one must define a few helper methods that can
execute and decode SQL statements. This is done by defining a variety of methods that execute
``SelectStatement``s and ``Statement``s.

For a full implementation, see the [StructuredQueriesSQLite][sq-sqlite] module in the library. You
should be able to adapt this sample code to execute StructuredQueries with a SQLite connection, or
even integrate StructuredQueries into a 3rd party SQLite library.

[sq-sqlite]: https://github.com/pointfreeco/swift-structured-queries/tree/main/Sources/StructuredQueriesSQLite

### Case Study: GRDB

We provide one first-party library that integrates StructuredQueries into SQLite, and that is in
our [SQLiteData] library, which is a lightweight replacement for SwiftData and
the `@Query` macro. It brings a suite of tools allow you to fetch and observe data from a database
in your feature code, and views automatically update when data in the database changes.

The integration of StructuredQueries into SQLiteData works in the manner outlined above, in
<doc:Integration#Case-Study-SQLite>. The code can be found [here][sq-sqlite-data], where you will
find a ``QueryDecoder`` conformance, as well as some helper methods for fetching data using
StructuredQueries and GRDB.

[SQLiteData: http://github.com/pointfreeco/sqlite-data
[sq-sqlite-data]: https://github.com/pointfreeco/sqlite-data/tree/main/Sources/StructuredQueriesGRDBCore

### Case Study: PostgresNIO

This package also contains a first-party integration module for PostgresNIO,
`StructuredQueriesPostgresNIO`. It extends both pooled `PostgresClient` values and
transaction-scoped `PostgresConnection` values with overloads that execute StructuredQueries
`Statement` and `SelectStatement` values.

Start a client's lifecycle in a long-running task before issuing queries, and cancel that task when
the client is no longer needed:

```swift
let client = PostgresClient(configuration: configuration)
let runTask = Task {
  await client.run()
}
defer { runTask.cancel() }
```

Typed queries start asynchronously and return a backpressure-aware sequence. Rows are decoded only
as they are requested:

```swift
let reminders = try await client.query(
  Reminder.where { !$0.isCompleted },
  logger: logger
)
for try await reminder in reminders {
  // Use reminder
}
```

The same typed queries are available on the connection passed to `withTransaction`, so every
statement in the closure uses the transaction's leased connection:

```swift
try await client.withTransaction(logger: logger) { connection in
  _ = try await connection.execute(
    Reminder.insert { reminder },
    logger: logger
  )
  var reminders: [Reminder] = []
  for try await reminder in try await connection.query(Reminder.all, logger: logger) {
    reminders.append(reminder)
  }
  return reminders
}
```

Use `execute` for DDL and INSERT, UPDATE, or DELETE statements without `RETURNING`. It drains the
command before returning and preserves PostgresNIO's native `PostgresQueryMetadata`, including the
command and affected-row count when Postgres supplies one:

```swift
if let metadata = try await client.execute(
  Reminder.where { $0.id.eq(id) }.delete(),
  logger: logger
) {
  print(metadata.command, metadata.rows as Any)
}
```

An empty StructuredQueries statement is a no-op and returns `nil` metadata. Statements with
`RETURNING` use `query` and stream their typed rows.

Cancelling `execute` stops the in-flight command by closing its connection. A pooled client replaces
that connection, while cancellation inside a transaction aborts the transaction.

Every query and execution overload accepts a per-query `Logger`, `file`, and `line`. The source
arguments default to the caller and are forwarded to PostgresNIO so errors and telemetry identify
the application call site. `PostgresClient` follows PostgresNIO by accepting an optional logger;
`PostgresConnection` requires one.

The integration binds and decodes booleans, signed integers, doubles, strings, dates, UUIDs, byte
arrays, and `NULL`. Unsigned integers are represented as signed Postgres integers and throw before
execution when a value exceeds `Int64.max`.

#### Postgres dialect support

StructuredQueries can construct SQL that is not valid in every database. The Postgres integration
tests the common subset used for selects, joins, predicates, ordering, inserts, updates, deletes,
`RETURNING`, bindings, and transactions. Importing `StructuredQueriesPostgresNIO` does not make all
core query-building APIs portable to Postgres.

In particular, `glob` emits SQLite's `GLOB` operator and `groupConcat` emits SQLite's
`group_concat` aggregate; neither is supported by this integration. Use the schema-safe `#sql`
macro for Postgres-native expressions that do not yet have a dedicated builder, and verify other
database-specific SQL against Postgres before using it in production.

See the module sources [here][sq-postgres] for a complete integration:

[sq-postgres]: https://github.com/pointfreeco/swift-structured-queries/tree/main/Sources/StructuredQueriesPostgresNIO
