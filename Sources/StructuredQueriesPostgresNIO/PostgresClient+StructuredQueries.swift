import Foundation
import PostgresNIO
import StructuredQueries

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension PostgresClient {
  public func query<S: SelectStatement>(
    _ query: S
  ) throws -> DecodedStatementSequence<S.From>
  where S.QueryValue == (), S.Joins == (), S.From.QueryOutput: Sendable {
    let queryFragment = query.selectStar().asSelect().query
    guard !queryFragment.isEmpty else {
      return DecodedStatementSequence<S.From>(client: self, query: nil)
    }
    return try DecodedStatementSequence<S.From>(
      client: self,
      query: PostgresQuery(queryFragment: queryFragment)
    )
  }

  public func query<S: Statement>(
    _ query: S
  ) throws -> DecodedStatementSequence<S.QueryValue>
  where S.QueryValue: QueryRepresentable, S.QueryValue.QueryOutput: Sendable {
    let queryFragment = query.query
    guard !queryFragment.isEmpty else {
      return DecodedStatementSequence<S.QueryValue>(client: self, query: nil)
    }
    return try DecodedStatementSequence<S.QueryValue>(
      client: self,
      query: PostgresQuery(queryFragment: queryFragment)
    )
  }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension PostgresClient {
  public func query<S: SelectStatement, each J: Table>(
    _ query: S
  ) throws -> DecodedTupleStatementSequence<S.From, repeat each J>
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable,
    S.From.QueryOutput: Sendable
  {
    let queryFragment = query.selectStar().asSelect().query
    guard !queryFragment.isEmpty else {
      return DecodedTupleStatementSequence<S.From, repeat each J>(client: self, query: nil)
    }
    return try DecodedTupleStatementSequence<S.From, repeat each J>(
      client: self,
      query: PostgresQuery(queryFragment: queryFragment)
    )
  }

  public func query<each V: QueryRepresentable>(
    _ query: some Statement<(repeat each V)>
  ) throws -> DecodedTupleStatementSequence<repeat each V>
  where repeat (each V).QueryOutput: Sendable {
    let queryFragment = query.query
    guard !queryFragment.isEmpty else {
      return DecodedTupleStatementSequence<repeat each V>(client: self, query: nil)
    }
    return try DecodedTupleStatementSequence<repeat each V>(
      client: self,
      query: PostgresQuery(queryFragment: queryFragment)
    )
  }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct DecodedStatementSequence<QueryValue: QueryRepresentable>: AsyncSequence
where QueryValue.QueryOutput: Sendable {
  public typealias Element = QueryValue.QueryOutput

  let client: PostgresClient
  let query: PostgresQuery?

  init(client: PostgresClient, query: PostgresQuery?) {
    self.client = client
    self.query = query
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(
      client: client,
      query: query,
      rows: nil,
      isFinished: false
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let client: PostgresClient
    let query: PostgresQuery?
    var rows: PostgresRowSequence.AsyncIterator?
    var isFinished: Bool

    public mutating func next() async throws -> Element? {
      guard !isFinished else { return nil }
      guard let query else {
        isFinished = true
        return nil
      }
      if rows == nil {
        rows = try await client.query(query).makeAsyncIterator()
      }
      guard var rows else { return nil }
      defer { self.rows = rows }
      guard let row = try await rows.next() else {
        isFinished = true
        return nil
      }
      var decoder = PostgresQueryDecoder(cells: Array(row))
      return try QueryValue(decoder: &decoder).queryOutput
    }
  }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
public struct DecodedTupleStatementSequence<each V: QueryRepresentable>: AsyncSequence
where repeat (each V).QueryOutput: Sendable {
  public typealias Element = (repeat (each V).QueryOutput)

  let client: PostgresClient
  let query: PostgresQuery?

  init(client: PostgresClient, query: PostgresQuery?) {
    self.client = client
    self.query = query
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(
      client: client,
      query: query,
      rows: nil,
      isFinished: false
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let client: PostgresClient
    let query: PostgresQuery?
    var rows: PostgresRowSequence.AsyncIterator?
    var isFinished: Bool

    public mutating func next() async throws -> Element? {
      guard !isFinished else { return nil }
      guard let query else {
        isFinished = true
        return nil
      }
      if rows == nil {
        rows = try await client.query(query).makeAsyncIterator()
      }
      guard var rows else { return nil }
      defer { self.rows = rows }
      guard let row = try await rows.next() else {
        isFinished = true
        return nil
      }
      var decoder = PostgresQueryDecoder(cells: Array(row))
      return try (repeat (each V)(decoder: &decoder).queryOutput)
    }
  }
}
