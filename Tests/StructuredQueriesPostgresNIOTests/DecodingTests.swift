import Foundation
import StructuredQueriesPostgresNIO
import Testing

@Suite struct DecodingTests {
  @Test func decodesCoreScalars() throws {
    let date = Date(timeIntervalSince1970: 123_456)
    let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    var bytesBuffer = ByteBufferAllocator().buffer(capacity: 4)
    bytesBuffer.writeBytes([0xDE, 0xAD, 0xBE, 0xEF])

    var decoder = PostgresQueryDecoder(
      cells: [
        cell(.init(int: 42), index: 0),
        cell(.init(int64: 43), index: 1),
        cell(.init(int64: 44), index: 2),
        cell(.init(double: 45.5), index: 3),
        cell(.init(bool: true), index: 4),
        cell(.init(string: "Blob"), index: 5),
        cell(.init(date: date), index: 6),
        cell(.init(uuid: uuid), index: 7),
        cell(.init(type: .bytea, value: bytesBuffer), index: 8),
      ]
    )

    #expect(try decoder.decode(Int.self) == 42)
    #expect(try decoder.decode(Int64.self) == 43)
    #expect(try decoder.decode(UInt64.self) == 44)
    #expect(try decoder.decode(Double.self) == 45.5)
    #expect(try decoder.decode(Bool.self) == true)
    #expect(try decoder.decode(String.self) == "Blob")
    #expect(try decoder.decode(Date.self) == date)
    #expect(try decoder.decode(UUID.self) == uuid)
    #expect(try decoder.decode([UInt8].self) == [0xDE, 0xAD, 0xBE, 0xEF])
  }

  @Test func decodesNullsAsNil() throws {
    var decoder = PostgresQueryDecoder(
      cells: [
        cell(.null, index: 0),
        cell(.null, index: 1),
        cell(.null, index: 2),
      ]
    )
    #expect(try decoder.decode(String.self) == nil)
    #expect(try decoder.decode(Int.self) == nil)
    #expect(try decoder.decode(Date.self) == nil)
  }

  @Test func queryRepresentableBoolDecodesFromPostgresBool() throws {
    var decoder = PostgresQueryDecoder(cells: [cell(.init(bool: true), index: 0)])
    #expect(try Bool(decoder: &decoder))
  }

  @Test func unsignedOverflowThrows() throws {
    var decoder = PostgresQueryDecoder(
      cells: [cell(.init(int64: -1), index: 0)]
    )

    do {
      _ = try decoder.decode(UInt64.self)
      #expect(Bool(false))
    } catch is UInt64OverflowError {
      #expect(Bool(true))
    }
  }
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
