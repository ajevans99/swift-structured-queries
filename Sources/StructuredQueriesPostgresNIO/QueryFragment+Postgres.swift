import Foundation
import PostgresNIO
import StructuredQueries

extension PostgresQuery {
  package init(queryFragment: QueryFragment) throws {
    let (sql, bindings) = queryFragment.prepare { "$\($0)" }
    self.init(
      unsafeSQL: sql,
      binds: try PostgresBindings(queryBindings: bindings)
    )
  }
}

extension PostgresBindings {
  package init(queryBindings: [QueryBinding]) throws {
    self.init(capacity: queryBindings.count)
    for binding in queryBindings {
      switch binding {
      case .blob(let value):
        try append(Data(value))
      case .bool(let value):
        append(value)
      case .date(let value):
        append(value)
      case .double(let value):
        append(value)
      case .int(let value):
        append(value)
      case .null:
        appendNull()
      case .text(let value):
        append(value)
      case .uint(let value) where value <= UInt64(Int64.max):
        append(Int64(value))
      case .uint(let value):
        throw Int64OverflowError(unsignedInteger: value)
      case .uuid(let value):
        append(value)
      case .invalid(let error):
        throw error.underlyingError
      }
    }
  }
}

package struct Int64OverflowError: Error {
  let unsignedInteger: UInt64
}
