#if CasePaths
  import CasePaths
  import StructuredQueries
  import Testing

  @Suite struct CasePathsCompatibilityTests {
    @Test func enumTableSupportsEmbeddingExtractionAndIteration() {
      let value = CompatibilityContent.allCasePaths.text.embed("Hello")
      let text: String? = value[case: \.text]
      #expect(text == "Hello")
      #expect(value.is(\.text))
      #expect(Array(CompatibilityContent.allCasePaths).count == 2)
      #expect(CompatibilityContent.allCasePaths[value] == \.text)
    }

    @Test func enumSelectionSupportsCasePaths() {
      let value = CompatibilityDetail.allCasePaths.count.embed(42)
      #expect(value[case: \.count] == 42)
      #expect(Array(CompatibilityDetail.allCasePaths).count == 2)
    }

    @Test func explicitCasePathableDoesNotDuplicateConformances() {
      let text: String? = ExplicitCompatibilityContent.text("Hello")[case: \.text]
      #expect(text == "Hello")
      #expect(Array(ExplicitCompatibilityContent.allCasePaths).count == 1)
    }
  }

  @Table private enum CompatibilityContent {
    case text(String)
    case count(Int)
  }

  @Selection private enum CompatibilityDetail {
    case title(String)
    case count(Int)
  }

  @CasePathable @Table private enum ExplicitCompatibilityContent {
    case text(String)
  }
#endif
