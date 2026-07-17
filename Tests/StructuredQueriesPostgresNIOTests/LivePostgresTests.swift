import Foundation
import StructuredQueriesPostgresNIO
import Testing

@Suite(.serialized)
struct LivePostgresTests {
  @Test func crudReturningJoinsAndMetadata() async throws {
    try await withPostgresClient { client, logger in
      try await resetTables(client, logger: logger)

      let createMetadata = try #require(
        try await client.execute(createTeams, logger: logger)
      )
      #expect(createMetadata.command == "CREATE TABLE")
      #expect(createMetadata.rows == nil)
      _ = try #require(try await client.execute(createUsers, logger: logger))

      let teamInsert = try #require(
        try await client.execute(
          PGTeam.insert {
            PGTeam(id: 1, name: "Core")
            PGTeam(id: 2, name: "Growth")
          },
          logger: logger
        )
      )
      #expect(teamInsert.command == "INSERT")
      #expect(teamInsert.rows == 2)

      let inserted = try await collect(
        try await client.query(
          PGUser
            .insert {
              PGUser(id: 1, name: "Blob", teamID: 1, score: 9.5, nickname: nil)
              PGUser(id: 2, name: "Stephen", teamID: 1, score: nil, nickname: "Steve")
            }
            .returning(\.self),
          logger: logger
        )
      )
      #expect(inserted.map(\.id) == [1, 2])
      #expect(inserted[0].nickname == nil)
      #expect(inserted[1].score == nil)

      let names = try await collect(
        try await client.query(PGUser.select(\.name).order(by: \.id), logger: logger)
      )
      #expect(names == ["Blob", "Stephen"])

      let joined = try await collect(
        try await client.query(
          PGUser
            .order(by: \.id)
            .join(PGTeam.all) { $0.teamID.eq($1.id) },
          logger: logger
        )
      )
      #expect(joined.map { "\($0.0.name):\($0.1.name)" } == ["Blob:Core", "Stephen:Core"])

      let updateMetadata = try #require(
        try await client.execute(
          PGUser.where { $0.id.eq(1) }.update { $0.name = #bind("Blob Sr.") },
          logger: logger
        )
      )
      #expect(updateMetadata.command == "UPDATE")
      #expect(updateMetadata.rows == 1)

      let updatedNames = try await collect(
        try await client.query(
          PGUser
            .where { $0.id.eq(2) }
            .update { $0.nickname = #bind(nil) }
            .returning(\.name),
          logger: logger
        )
      )
      #expect(updatedNames == ["Stephen"])

      let deletedIDs = try await collect(
        try await client.query(
          PGUser.where { $0.id.eq(2) }.delete().returning(\.id),
          logger: logger
        )
      )
      #expect(deletedIDs == [2])

      let deleteMetadata = try #require(
        try await client.execute(PGUser.delete(), logger: logger)
      )
      #expect(deleteMetadata.command == "DELETE")
      #expect(deleteMetadata.rows == 1)
    }
  }

  @Test func scalarBindingsAndNulls() async throws {
    try await withPostgresClient { client, logger in
      let date = Date(timeIntervalSince1970: 1_234_567)
      let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
      let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
      let nullableString: String? = nil

      #expect(
        try await collect(
          try await client.query(#sql("SELECT \(bind: true)", as: Bool.self), logger: logger)
        ) == [true]
      )
      #expect(
        try await collect(
          try await client.query(#sql("SELECT \(bind: 42)", as: Int.self), logger: logger)
        ) == [42]
      )
      #expect(
        try await collect(
          try await client.query(#sql("SELECT \(bind: Int64(43))", as: Int64.self), logger: logger)
        ) == [43]
      )
      #expect(
        try await collect(
          try await client.query(#sql("SELECT \(bind: 44.5)", as: Double.self), logger: logger)
        ) == [44.5]
      )
      #expect(
        try await collect(
          try await client.query(#sql("SELECT \(bind: "Blob")", as: String.self), logger: logger)
        ) == ["Blob"]
      )
      #expect(
        try await collect(
          try await client.query(#sql("SELECT \(bind: date)", as: Date.self), logger: logger)
        ) == [date]
      )
      #expect(
        try await collect(
          try await client.query(#sql("SELECT \(bind: uuid)", as: UUID.self), logger: logger)
        ) == [uuid]
      )
      #expect(
        try await collect(
          try await client.query(#sql("SELECT \(bind: bytes)", as: [UInt8].self), logger: logger)
        ) == [bytes]
      )
      #expect(
        try await collect(
          try await client.query(
            #sql("SELECT \(#bind(nullableString, as: String?.self))", as: String?.self),
            logger: logger
          )
        ) == [nil]
      )
    }
  }

  @Test func transactionsCommitAndRollback() async throws {
    try await withPostgresClient { client, logger in
      try await resetTables(client, logger: logger)
      _ = try #require(try await client.execute(createTeams, logger: logger))
      _ = try #require(try await client.execute(createUsers, logger: logger))
      _ = try #require(
        try await client.execute(PGTeam.insert { PGTeam(id: 1, name: "Core") }, logger: logger)
      )

      let committedCount = try await client.withTransaction(logger: logger) { connection in
        _ = try #require(
          try await connection.execute(
            PGUser.insert {
              PGUser(id: 1, name: "Blob", teamID: 1, score: nil, nickname: nil)
            },
            logger: logger
          )
        )
        return try await collect(try await connection.query(PGUser.all, logger: logger)).count
      }
      #expect(committedCount == 1)
      #expect(try await collect(try await client.query(PGUser.all, logger: logger)).count == 1)

      await #expect(throws: (any Error).self) {
        try await client.withTransaction(logger: logger) { connection in
          _ = try #require(
            try await connection.execute(
              PGUser.insert {
                PGUser(id: 2, name: "Stephen", teamID: 1, score: nil, nickname: nil)
              },
              logger: logger
            )
          )
          throw Rollback()
        }
      }
      #expect(try await collect(try await client.query(PGUser.all, logger: logger)).count == 1)
    }
  }

  @Test func constraintFailuresKeepCallerLocation() async throws {
    try await withPostgresClient { client, logger in
      try await resetTables(client, logger: logger)
      _ = try #require(try await client.execute(createTeams, logger: logger))
      _ = try #require(try await client.execute(createUsers, logger: logger))
      _ = try #require(
        try await client.execute(PGTeam.insert { PGTeam(id: 1, name: "Core") }, logger: logger)
      )

      do {
        _ = try await client.execute(
          PGTeam.insert { PGTeam(id: 1, name: "Duplicate") },
          logger: logger,
          file: "ConstraintTests.swift",
          line: 123
        )
        Issue.record("Expected a unique-constraint failure")
      } catch let error as PSQLError {
        #expect(error.serverInfo?[.sqlState] == "23505")
        #expect(error.file == "ConstraintTests.swift")
        #expect(error.line == 123)
      }

      do {
        _ = try await client.execute(
          PGUser.insert {
            PGUser(id: 1, name: "Blob", teamID: 999, score: nil, nickname: nil)
          },
          logger: logger
        )
        Issue.record("Expected a foreign-key failure")
      } catch let error as PSQLError {
        #expect(error.serverInfo?[.sqlState] == "23503")
      }
    }
  }

  @Test func earlyTerminationAndDecodeFailureReleaseTheLease() async throws {
    try await withPostgresClient(maximumConnections: 1) { client, logger in
      do {
        let sequence = try await client.query(
          #sql("SELECT generate_series(1, 10000)", as: Int.self),
          logger: logger
        )
        var iterator = sequence.makeAsyncIterator()
        #expect(try await iterator.next() == 1)
      }
      #expect(
        try await collect(
          try await client.query(#sql("SELECT 2", as: Int.self), logger: logger)
        ) == [2]
      )

      do {
        let sequence = try await client.query(
          #sql("SELECT 'not-an-integer'", as: Int.self),
          logger: logger
        )
        var iterator = sequence.makeAsyncIterator()
        await #expect(throws: (any Error).self) {
          _ = try await iterator.next()
        }
      }
      #expect(
        try await collect(
          try await client.query(#sql("SELECT 3", as: Int.self), logger: logger)
        ) == [3]
      )
    }
  }

  @Test func cancellationStopsExecutionAndReleasesTheLease() async throws {
    try await withPostgresClient(maximumConnections: 1) { client, logger in
      let clock = ContinuousClock()
      let start = clock.now
      let task = Task {
        try await client.execute(
          #sql("SELECT pg_sleep(10)", as: Void.self),
          logger: logger
        )
      }
      try await Task.sleep(for: .milliseconds(100))
      task.cancel()
      await #expect(throws: CancellationError.self) {
        _ = try await task.value
      }
      #expect(start.duration(to: clock.now) < .seconds(5))
      #expect(
        try await collect(
          try await client.query(#sql("SELECT 4", as: Int.self), logger: logger)
        ) == [4]
      )
    }
  }
}

@Table("sq_pg_users")
private struct PGUser: Equatable, Identifiable, Sendable {
  let id: Int
  var name: String
  var teamID: Int
  var score: Double?
  var nickname: String?
}

@Table("sq_pg_teams")
private struct PGTeam: Equatable, Identifiable, Sendable {
  let id: Int
  var name: String
}

private let createTeams = #sql(
  """
  CREATE TABLE "sq_pg_teams" (
    "id" BIGINT PRIMARY KEY,
    "name" TEXT NOT NULL UNIQUE
  )
  """,
  as: Void.self
)

private let createUsers = #sql(
  """
  CREATE TABLE "sq_pg_users" (
    "id" BIGINT PRIMARY KEY,
    "name" TEXT NOT NULL,
    "teamID" BIGINT NOT NULL REFERENCES "sq_pg_teams"("id"),
    "score" DOUBLE PRECISION,
    "nickname" TEXT
  )
  """,
  as: Void.self
)

private struct MissingPostgresConfiguration: Error {}
private struct Rollback: Error {}

private struct PostgresLiveConfiguration {
  let host: String
  let port: Int
  let username: String
  let password: String?
  let database: String

  init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
    guard
      let host = environment["POSTGRES_HOST"],
      let username = environment["POSTGRES_USER"],
      let database = environment["POSTGRES_DB"]
    else {
      throw MissingPostgresConfiguration()
    }
    self.host = host
    self.port = Int(environment["POSTGRES_PORT"] ?? "") ?? 5432
    self.username = username
    self.password = environment["POSTGRES_PASSWORD"]
    self.database = database
  }
}

private func withPostgresClient<Result>(
  maximumConnections: Int = 4,
  _ operation: (PostgresClient, Logger) async throws -> Result
) async throws -> Result {
  let live = try PostgresLiveConfiguration()
  var configuration = PostgresClient.Configuration(
    host: live.host,
    port: live.port,
    username: live.username,
    password: live.password,
    database: live.database,
    tls: .disable
  )
  configuration.options.maximumConnections = maximumConnections
  let logger = Logger(label: "StructuredQueriesPostgresNIOTests")
  let client = PostgresClient(configuration: configuration, backgroundLogger: logger)
  let runTask = Task {
    await client.run()
  }
  defer { runTask.cancel() }
  await Task.yield()
  return try await operation(client, logger)
}

private func resetTables(_ client: PostgresClient, logger: Logger) async throws {
  _ = try await client.execute(
    #sql("DROP TABLE IF EXISTS \"sq_pg_users\"", as: Void.self),
    logger: logger
  )
  _ = try await client.execute(
    #sql("DROP TABLE IF EXISTS \"sq_pg_teams\"", as: Void.self),
    logger: logger
  )
}

private func collect<S: AsyncSequence>(_ sequence: S) async throws -> [S.Element] {
  var elements: [S.Element] = []
  for try await element in sequence {
    elements.append(element)
  }
  return elements
}
