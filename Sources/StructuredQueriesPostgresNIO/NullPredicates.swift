public import StructuredQueriesCore

extension QueryExpression where QueryValue: QueryRepresentable {
  /// Returns whether this expression is SQL `NULL` using PostgreSQL's `IS NULL` syntax.
  public func isNull() -> some QueryExpression<Bool> {
    SQLQueryExpression("(\(self)) IS NULL", as: Bool.self)
  }

  /// Returns whether this expression is not SQL `NULL` using PostgreSQL's `IS NOT NULL` syntax.
  public func isNotNull() -> some QueryExpression<Bool> {
    SQLQueryExpression("(\(self)) IS NOT NULL", as: Bool.self)
  }
}
