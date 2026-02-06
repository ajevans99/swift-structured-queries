import Foundation
import PostgresNIO
import StructuredQueries

package struct PostgresQueryDecoder: QueryDecoder {
  var rows: PostgresRowSequence.AsyncIterator?
  var row: AnyIterator<PostgresCell>?

  init(rows: PostgresRowSequence.AsyncIterator) {
    self.rows = rows
  }

  package init(cells: [PostgresCell]) {
    self.rows = nil
    self.row = AnyIterator(cells.makeIterator())
  }

  package mutating func next() async throws -> Bool {
    guard var rows else {
      return false
    }
    defer { self.rows = rows }
    guard let row = try await rows.next() else {
      self.row = nil
      return false
    }
    self.row = AnyIterator(row.makeIterator())
    return true
  }

  package mutating func decode(_ columnType: [UInt8].Type) throws -> [UInt8]? {
    try decodeValue(Data.self).map(Array.init)
  }

  package mutating func decode(_ columnType: Bool.Type) throws -> Bool? {
    try decodeValue(Bool.self)
  }

  package mutating func decode(_ columnType: Date.Type) throws -> Date? {
    try decodeValue(Date.self)
  }

  package mutating func decode(_ columnType: Double.Type) throws -> Double? {
    try decodeValue(Double.self)
  }

  package mutating func decode(_ columnType: Int.Type) throws -> Int? {
    try decodeValue(Int.self)
  }

  package mutating func decode(_ columnType: Int64.Type) throws -> Int64? {
    try decodeValue(Int64.self)
  }

  package mutating func decode(_ columnType: String.Type) throws -> String? {
    try decodeValue(String.self)
  }

  package mutating func decode(_ columnType: UInt64.Type) throws -> UInt64? {
    guard let signedInteger = try decode(Int64.self) else {
      return nil
    }
    guard signedInteger >= 0 else {
      throw UInt64OverflowError(signedInteger: signedInteger)
    }
    return UInt64(signedInteger)
  }

  package mutating func decode(_ columnType: UUID.Type) throws -> UUID? {
    try decodeValue(UUID.self)
  }

  private mutating func decodeValue<T: PostgresDecodable>(_ columnType: T.Type) throws -> T?
  where T._DecodableType == T {
    guard let cell = row?.next() else {
      return nil
    }
    return try cell.decode(T?.self)
  }
}

package struct UInt64OverflowError: Error {
  let signedInteger: Int64
}
