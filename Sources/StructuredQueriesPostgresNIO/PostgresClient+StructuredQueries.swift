import Foundation
import PostgresNIO
import StructuredQueries

private struct SendableMetatype<T>: @unchecked Sendable {
  let type: T.Type
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension PostgresClient {
  public func query<S: SelectStatement, each J: Table>(
    _ query: S
  ) throws -> AsyncThrowingStream<(_: S.From.QueryOutput, repeat (each J).QueryOutput), any Error>
  where
    S.QueryValue == (),
    S.Joins == (repeat each J),
    repeat (each J).QueryOutput: Sendable,
    S.From.QueryOutput: Sendable
  {
    try self.query(query.selectStar().asSelect())
  }

  public func query<S: SelectStatement>(_ query: S) throws -> AsyncThrowingStream<S.From.QueryOutput, any Error>
  where S.QueryValue == (), S.Joins == (), S.From.QueryOutput: Sendable {
    try self.query(query.selectStar().asSelect())
  }

  public func query<S: Statement>(_ query: S) throws -> AsyncThrowingStream<S.QueryValue.QueryOutput, any Error>
  where S.QueryValue: QueryRepresentable, S.QueryValue.QueryOutput: Sendable {
    let postgresQuery = try PostgresQuery(queryFragment: query.query)
    let queryValue = SendableMetatype(type: S.QueryValue.self)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let rows = try await self.query(postgresQuery)
          var decoder = PostgresQueryDecoder(rows: rows.makeAsyncIterator())
          while try await decoder.next() {
            continuation.yield(try decoder.decodeColumns(queryValue.type))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  public func query<each V: QueryRepresentable>(
    _ query: some Statement<(repeat each V)>
  ) throws -> AsyncThrowingStream<(repeat (each V).QueryOutput), any Error>
  where repeat (each V).QueryOutput: Sendable {
    let postgresQuery = try PostgresQuery(queryFragment: query.query)
    let queryValue = SendableMetatype(type: (repeat each V).self)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let rows = try await self.query(postgresQuery)
          var decoder = PostgresQueryDecoder(rows: rows.makeAsyncIterator())
          while try await decoder.next() {
            continuation.yield(try decoder.decodeColumns(queryValue.type))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
