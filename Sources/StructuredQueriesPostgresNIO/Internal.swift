@usableFromInline
package struct Int64OverflowError: Error {
  package let unsignedInteger: UInt64

  @usableFromInline
  package init(unsignedInteger: UInt64) {
    self.unsignedInteger = unsignedInteger
  }
}

@usableFromInline
package struct UInt64OverflowError: Error {
  package let signedInteger: Int64

  @usableFromInline
  package init(signedInteger: Int64) {
    self.signedInteger = signedInteger
  }
}
