import Foundation
import StructuredQueriesPostgresNIO
import Testing

@Suite struct NullPredicateTests {
  @Test func rendersBareNullWithoutBindings() throws {
    let expressions = [
      NullPredicateRecord.columns.date.isNull().queryFragment,
      NullPredicateRecord.columns.uuid.isNotNull().queryFragment,
      NullPredicateRecord.columns.text.isNull().queryFragment,
    ]
    let expected = [
      #"("nullPredicateRecords"."date") IS NULL"#,
      #"("nullPredicateRecords"."uuid") IS NOT NULL"#,
      #"("nullPredicateRecords"."text") IS NULL"#,
    ]
    for (expression, sql) in zip(expressions, expected) {
      let query = try PostgresQuery(queryFragment: expression)
      #expect(query.sql == sql)
      #expect(query.binds.count == 0)
    }
  }

  @Test func preservesExpressionBindingsAndCoreOperators() throws {
    let expression = #bind("Hello", as: String?.self)
    let query = try PostgresQuery(queryFragment: expression.isNotNull().queryFragment)
    #expect(query.sql == "($1) IS NOT NULL")
    #expect(query.binds.count == 1)

    let core = try PostgresQuery(
      queryFragment: NullPredicateRecord.columns.text.is(nil).queryFragment
    )
    #expect(core.sql == #"("nullPredicateRecords"."text") IS (NULL)"#)
    let equality = try PostgresQuery(queryFragment: expression.is(expression).queryFragment)
    #expect(equality.sql == "($1) IS ($2)")
  }
}

@Table private struct NullPredicateRecord {
  var date: Date?
  var uuid: UUID?
  var text: String?
}
