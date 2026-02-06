import Foundation
import StructuredQueries
import StructuredQueriesPostgresNIO
import Testing

@Suite struct LivePostgresTests {
  @Test func smoke() async throws {
    guard let configuration = PostgresLiveConfiguration() else {
      return
    }

    let client = PostgresClient(
      configuration: .init(
        host: configuration.host,
        port: configuration.port,
        username: configuration.username,
        password: configuration.password,
        database: configuration.database,
        tls: .disable
      )
    )
    let runTask = Task {
      await client.run()
    }
    defer { runTask.cancel() }

    _ = try await client.query(
      PostgresQuery(
        unsafeSQL: """
          CREATE TEMP TABLE "pg_teams" (
            "id" BIGINT PRIMARY KEY,
            "name" TEXT NOT NULL
          );
          """
      )
    ).collect()

    _ = try await client.query(
      PostgresQuery(
        unsafeSQL: """
          CREATE TEMP TABLE "pg_users" (
            "id" BIGINT PRIMARY KEY,
            "name" TEXT NOT NULL,
            "teamID" BIGINT NOT NULL REFERENCES "pg_teams"("id")
          );
          """
      )
    ).collect()

    _ = try await client.query(
      PostgresQuery(
        unsafeSQL: """
          INSERT INTO "pg_teams" ("id", "name")
          VALUES (1, 'Core');
          """
      )
    ).collect()

    _ = try await client.query(
      PostgresQuery(
        unsafeSQL: """
          INSERT INTO "pg_users" ("id", "name", "teamID")
          VALUES (1, 'Blob', 1), (2, 'Stephen', 1);
          """
      )
    ).collect()

    let users = try await collect(try client.query(PGUser.all))
    #expect(users.count == 2)

    let names = try await collect(try client.query(PGUser.select { $0.name }))
    #expect(names.sorted() == ["Blob", "Stephen"])

    let tuples = try await collect(try client.query(PGUser.select { ($0.id, $0.name) }))
    #expect(tuples.count == 2)

    let joined = try await collect(
      try client.query(
        PGUser
          .join(PGTeam.all) { $0.teamID.eq($1.id) }
      )
    )
    #expect(joined.count == 2)
  }
}

@Table("pg_users")
private struct PGUser: Codable, Equatable, Identifiable {
  let id: Int
  var name: String
  var teamID: Int
}

@Table("pg_teams")
private struct PGTeam: Codable, Equatable, Identifiable {
  let id: Int
  var name: String
}

private struct PostgresLiveConfiguration {
  let host: String
  let port: Int
  let username: String
  let password: String?
  let database: String

  init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
    guard
      let host = environment["POSTGRES_HOST"],
      let username = environment["POSTGRES_USER"],
      let database = environment["POSTGRES_DB"]
    else {
      return nil
    }
    self.host = host
    self.port = Int(environment["POSTGRES_PORT"] ?? "") ?? 5432
    self.username = username
    self.password = environment["POSTGRES_PASSWORD"]
    self.database = database
  }
}

private func collect<S: AsyncSequence>(_ sequence: S) async throws -> [S.Element] {
  var elements: [S.Element] = []
  for try await element in sequence {
    elements.append(element)
  }
  return elements
}
