//  Ask for Mac — MIT licensed. See LICENSE.
//
//  In-module test kit: `askmac selftest` runs without Xcode; Tests/ bridges to XCTest with it.
//  Every case runs against its own temporary databases and history folder, never the real ones.

import Foundation

final class T {
    private(set) var failures: [String] = []
    private(set) var checks = 0
    var skipped: String?
    func check(_ c: @autoclosure () -> Bool, _ what: String, file: StaticString = #fileID, line: UInt = #line) { checks += 1; if !c() { failures.append("\(what)  (\(file):\(line))") } }
    func equal<E: Equatable>(_ a: E, _ b: E, _ what: String, file: StaticString = #fileID, line: UInt = #line) { checks += 1; if a != b { failures.append("\(what): got \(a), expected \(b)  (\(file):\(line))") } }
    func fail(_ what: String, file: StaticString = #fileID, line: UInt = #line) { checks += 1; failures.append("\(what)  (\(file):\(line))") }
    func skip(_ why: String) { skipped = why }
}

struct TestCase { let name: String; let run: @MainActor (T) throws -> Void }
struct TestSuite { let name: String; let cases: [TestCase] }

enum TestKit {
    static var suites: [TestSuite] { [QuerySuite.suite, ExtractSuite.suite, RankSuite.suite, PipelineSuite.suite] }

    struct Result { let suite: String, name: String, failures: [String], skipped: String?, checks: Int, ms: Double; var passed: Bool { failures.isEmpty && skipped == nil } }

    /// A fresh temporary directory per case; removed afterwards.
    static func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("askmac-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @MainActor
    static func run(filter: String? = nil) -> [Result] {
        var out: [Result] = []
        for s in suites {
            for c in s.cases {
                let full = "\(s.name)/\(c.name)"
                if let filter, !full.localizedCaseInsensitiveContains(filter) { continue }
                let t = T(); let start = Date()
                let dir = tempDir()
                Prefs.defaults = UserDefaults(suiteName: "com.keithadler.askmac.selftest")!
                Prefs.defaults.removePersistentDomain(forName: "com.keithadler.askmac.selftest")
                Prefs.folders = [dir.path]; Ask.useSpotlight = false; CLI.quiet = true; Ask.previous = nil
                do { try c.run(t) } catch { t.fail("threw \(error)") }
                Prefs.defaults = .standard; Ask.useSpotlight = true; CLI.quiet = false
                try? FileManager.default.removeItem(at: dir)
                out.append(Result(suite: s.name, name: c.name, failures: t.failures, skipped: t.skipped, checks: t.checks, ms: Date().timeIntervalSince(start) * 1000))
            }
        }
        return out
    }

    static func report(_ results: [Result], json: Bool) -> Int32 {
        let failed = results.filter { !$0.failures.isEmpty }
        if json {
            print(CLI.json(["passed": results.filter(\.passed).count, "failed": failed.count, "checks": results.reduce(0) { $0 + $1.checks },
                            "results": results.map { ["suite": $0.suite, "name": $0.name, "failures": $0.failures, "ms": Int($0.ms)] }]))
        } else {
            var last = ""
            for r in results {
                if r.suite != last { print(r.suite); last = r.suite }
                print(String(format: "  %@ %@ (%d checks, %.0f ms)", r.skipped != nil ? "–" : (r.failures.isEmpty ? "✓" : "✗"), r.name, r.checks, r.ms))
                for f in r.failures { print("      \(f)") }
            }
            print("\(results.filter(\.passed).count) passed, \(failed.count) failed, \(results.reduce(0) { $0 + $1.checks }) checks")
        }
        return failed.isEmpty ? 0 : 2
    }

    static func list() { for s in suites { for c in s.cases { print("\(s.name)/\(c.name)") } } }
}


