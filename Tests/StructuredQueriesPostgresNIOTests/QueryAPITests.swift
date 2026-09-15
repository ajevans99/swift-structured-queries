import StructuredQueries
import StructuredQueriesPostgresNIO
import Testing

@Suite struct QueryAPITests {
  @Test func statementCompilesToPostgresQuery() throws {
    let statement = #sql(
      """
      SELECT \(1), \(bind: "Blob"), \(bind: true)
      """,
      as: (Int, String, Bool).self
    )
    let query = try PostgresQuery(queryFragment: statement.query)
    #expect(query.sql == "SELECT $1, $2, $3")
    #expect(query.binds.count == 3)
  }

  @Test func tupleDecodeColumns() throws {
    var decoder = PostgresQueryDecoder(
      cells: [
        cell(.init(int: 1), index: 0),
        cell(.init(string: "Blob"), index: 1),
      ]
    )
    let (id, title) = try decoder.decodeColumns((Int, String).self)
    #expect(id == 1)
    #expect(title == "Blob")
  }

  @Test func supportedSelectSQL() throws {
    let statement =
      EmptyRecord
      .where { $0.id.eq(42) }
      .order { $0.id.desc() }
      .select(\.id)
    let query = try PostgresQuery(queryFragment: statement.query)
    #expect(
      query.sql
        == """
        SELECT "emptyRecords"."id"
        FROM "emptyRecords"
        WHERE (("emptyRecords"."id") = ($1))
        ORDER BY "emptyRecords"."id" DESC
        """
    )
    #expect(query.binds.count == 1)
  }

  @Test func emptyExecutionIsANoOp() async throws {
    let client = PostgresClient(
      configuration: .init(
        host: "localhost",
        username: "unused",
        password: nil,
        database: nil,
        tls: .disable
      )
    )

    let metadata = try await client.execute(EmptyRecord.insert { [] })
    #expect(metadata == nil)
  }

  @Test func returningBuildersRemainAvailableWithoutSQLite() throws {
    let insert = EmptyRecord.insert { EmptyRecord(id: 42) }
    let update = EmptyRecord.update { $0.id = #bind(42) }
    let delete = EmptyRecord.delete()

    let statements = [
      insert.returning(\.self).query,
      insert.returning { ($0.id, $0.id) }.query,
      update.returning(\.self).query,
      update.returning { ($0.id, $0.id) }.query,
      delete.returning(\.self).query,
      delete.returning { ($0.id, $0.id) }.query,
    ]
    for (index, statement) in statements.enumerated() {
      let query = try PostgresQuery(queryFragment: statement)
      let expected = index.isMultiple(of: 2) ? #"RETURNING "id""# : #"RETURNING "id", "id""#
      #expect(query.sql.hasSuffix(expected))
      #expect(query.binds.count == (index < 4 ? 1 : 0))
    }
  }
}

@Table
private struct EmptyRecord: Sendable {
  var id: Int
}

private func cell(_ data: PostgresData, index: Int) -> PostgresCell {
  PostgresCell(
    bytes: data.value,
    dataType: data.type,
    format: data.formatCode,
    columnName: "c\(index)",
    columnIndex: index
  )
}
