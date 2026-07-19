import Foundation
import StructuredQueries
import StructuredQueriesPostgresNIO
import Testing

@Suite struct BindingsTests {
  @Test func placeholderSynthesis() throws {
    let fragment: QueryFragment = "SELECT \(.int(1)), \(.text("Blob")), \(.null)"
    let query = try PostgresQuery(queryFragment: fragment)
    #expect(query.sql == "SELECT $1, $2, $3")
    #expect(query.binds.count == 3)
  }

  @Test func coreBindings() throws {
    let date = Date(timeIntervalSince1970: 123_456)
    let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    let bindings: [QueryBinding] = [
      .blob([0xDE, 0xAD, 0xBE, 0xEF]),
      .bool(true),
      .double(1.5),
      .int(42),
      .null,
      .text("Blob"),
      .date(date),
      .uuid(uuid),
      .uint(123),
    ]
    let postgresBindings = try PostgresBindings(queryBindings: bindings)
    #expect(postgresBindings.count == bindings.count)
  }

  @Test func invalidBindingThrowsUnderlyingError() throws {
    let bindings: [QueryBinding] = [.invalid(InvalidBindingError())]
    do {
      _ = try PostgresBindings(queryBindings: bindings)
      #expect(Bool(false))
    } catch is InvalidBindingError {
      #expect(Bool(true))
    }
  }

  @Test func uintOverflowThrows() throws {
    do {
      _ = try PostgresBindings(queryBindings: [.uint(UInt64.max)])
      #expect(Bool(false))
    } catch is Int64OverflowError {
      #expect(Bool(true))
    }
  }
}

private struct InvalidBindingError: Error {}
