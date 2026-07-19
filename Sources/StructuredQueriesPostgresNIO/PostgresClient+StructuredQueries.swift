internal import Logging
public import PostgresNIO
public import StructuredQueriesCore

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension PostgresClient {
  public func query<S: SelectStatement>(
    _ query: S,
    logger: Logger? = nil,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> AsyncThrowingMapSequence<PostgresRowSequence, S.From.QueryOutput>
  where S.QueryValue == (), S.Joins == (), S.From: Sendable, S.From.QueryOutput: Sendable {
    let queryFragment = query.selectStar().asSelect().query
    return try await decode(
      rows(for: queryFragment, logger: logger, file: file, line: line),
      as: S.From.self
    )
  }

  public func query<S: Statement>(
    _ query: S,
    logger: Logger? = nil,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> AsyncThrowingMapSequence<PostgresRowSequence, S.QueryValue.QueryOutput>
  where
    S.QueryValue: QueryRepresentable & Sendable,
    S.QueryValue.QueryOutput: Sendable
  {
    return try await decode(
      rows(for: query.query, logger: logger, file: file, line: line),
      as: S.QueryValue.self
    )
  }

  public func execute<S: Statement>(
    _ statement: S,
    logger: Logger? = nil,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> PostgresQueryMetadata?
  where S.QueryValue == () {
    guard !statement.query.isEmpty else { return nil }
    let logger = logger ?? postgresLoggingDisabled
    return try await withConnection { connection in
      try await connection.execute(statement, logger: logger, file: file, line: line)
    }
  }

  private func rows(
    for queryFragment: QueryFragment,
    logger: Logger?,
    file: String,
    line: Int
  ) async throws -> PostgresRowSequence {
    return try await query(
      PostgresQuery(queryFragment: queryFragment),
      logger: logger,
      file: file,
      line: line
    )
  }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension PostgresClient {
  public func query<S: SelectStatement, each J: Table & Sendable>(
    _ query: S,
    logger: Logger? = nil,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> AsyncThrowingMapSequence<
    PostgresRowSequence, (S.From.QueryOutput, repeat (each J).QueryOutput)
  >
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable,
    S.From: Sendable,
    S.From.QueryOutput: Sendable
  {
    let queryFragment = query.selectStar().asSelect().query
    return try await decode(
      rows(for: queryFragment, logger: logger, file: file, line: line),
      as: (S.From, repeat each J).self
    )
  }

  public func query<each V: QueryRepresentable & Sendable>(
    _ query: some Statement<(repeat each V)>,
    logger: Logger? = nil,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> AsyncThrowingMapSequence<
    PostgresRowSequence, (repeat (each V).QueryOutput)
  >
  where repeat (each V).QueryOutput: Sendable {
    return try await decode(
      rows(for: query.query, logger: logger, file: file, line: line),
      as: (repeat each V).self
    )
  }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension PostgresConnection {
  public func query<S: SelectStatement>(
    _ query: S,
    logger: Logger,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> AsyncThrowingMapSequence<PostgresRowSequence, S.From.QueryOutput>
  where S.QueryValue == (), S.Joins == (), S.From: Sendable, S.From.QueryOutput: Sendable {
    let queryFragment = query.selectStar().asSelect().query
    return try await decode(
      rows(for: queryFragment, logger: logger, file: file, line: line),
      as: S.From.self
    )
  }

  public func query<S: Statement>(
    _ query: S,
    logger: Logger,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> AsyncThrowingMapSequence<PostgresRowSequence, S.QueryValue.QueryOutput>
  where
    S.QueryValue: QueryRepresentable & Sendable,
    S.QueryValue.QueryOutput: Sendable
  {
    return try await decode(
      rows(for: query.query, logger: logger, file: file, line: line),
      as: S.QueryValue.self
    )
  }

  public func execute<S: Statement>(
    _ statement: S,
    logger: Logger,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> PostgresQueryMetadata?
  where S.QueryValue == () {
    guard !statement.query.isEmpty else { return nil }
    let query = try PostgresQuery(queryFragment: statement.query)
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      do {
        let metadata =
          try await self.query(query, logger: logger, file: file, line: line) { _ in }.get()
        try Task.checkCancellation()
        return metadata
      } catch {
        try Task.checkCancellation()
        throw error
      }
    } onCancel: {
      self.close().whenComplete { _ in }
    }
  }

  private func rows(
    for queryFragment: QueryFragment,
    logger: Logger,
    file: String,
    line: Int
  ) async throws -> PostgresRowSequence {
    return try await query(
      PostgresQuery(queryFragment: queryFragment),
      logger: logger,
      file: file,
      line: line
    )
  }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension PostgresConnection {
  public func query<S: SelectStatement, each J: Table & Sendable>(
    _ query: S,
    logger: Logger,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> AsyncThrowingMapSequence<
    PostgresRowSequence, (S.From.QueryOutput, repeat (each J).QueryOutput)
  >
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable,
    S.From: Sendable,
    S.From.QueryOutput: Sendable
  {
    let queryFragment = query.selectStar().asSelect().query
    return try await decode(
      rows(for: queryFragment, logger: logger, file: file, line: line),
      as: (S.From, repeat each J).self
    )
  }

  public func query<each V: QueryRepresentable & Sendable>(
    _ query: some Statement<(repeat each V)>,
    logger: Logger,
    file: String = #fileID,
    line: Int = #line
  ) async throws -> AsyncThrowingMapSequence<
    PostgresRowSequence, (repeat (each V).QueryOutput)
  >
  where repeat (each V).QueryOutput: Sendable {
    return try await decode(
      rows(for: query.query, logger: logger, file: file, line: line),
      as: (repeat each V).self
    )
  }
}

private func decode<QueryValue: QueryRepresentable & Sendable>(
  _ rows: PostgresRowSequence,
  as queryValue: QueryValue.Type
) -> AsyncThrowingMapSequence<PostgresRowSequence, QueryValue.QueryOutput>
where QueryValue.QueryOutput: Sendable {
  rows.map { row in
    var decoder = PostgresQueryDecoder(cells: Array(row))
    return try QueryValue(decoder: &decoder).queryOutput
  }
}

private func decode<each QueryValue: QueryRepresentable & Sendable>(
  _ rows: PostgresRowSequence,
  as queryValue: (repeat each QueryValue).Type
) -> AsyncThrowingMapSequence<
  PostgresRowSequence, (repeat (each QueryValue).QueryOutput)
>
where repeat (each QueryValue).QueryOutput: Sendable {
  rows.map { row in
    var decoder = PostgresQueryDecoder(cells: Array(row))
    return try (repeat (each QueryValue)(decoder: &decoder).queryOutput)
  }
}

private let postgresLoggingDisabled = Logger(
  label: "StructuredQueriesPostgresNIO-do-not-log",
  factory: { _ in SwiftLogNoOpLogHandler() }
)
