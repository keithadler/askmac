import XCTest
@testable import AskMac

final class SuiteTests: XCTestCase {
    @MainActor private func runSuite(_ name: String) {
        let results = TestKit.run(filter: name + "/")
        XCTAssertFalse(results.isEmpty)
        for r in results { for f in r.failures { XCTFail("\(r.suite)/\(r.name): \(f)") } }
    }
    @MainActor func testQuery() { runSuite("Query") }
    @MainActor func testExtract() { runSuite("Extract") }
    @MainActor func testRank() { runSuite("Rank") }
    @MainActor func testPipeline() { runSuite("Pipeline") }
}
