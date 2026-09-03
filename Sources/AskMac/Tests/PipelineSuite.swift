//  Ask for Mac — MIT licensed. See LICENSE.
import Foundation

enum PipelineSuite {
    static func seed(_ dir: URL) throws {
        try "Lease agreement for 12 Woodland Ave.\n\nSecurity deposit: $2,400, due at signing. Rent $1,950 monthly.\n\nTenant: Sam Rivera.".write(to: dir.appendingPathComponent("Lease Woodland Ave.txt"), atomically: true, encoding: .utf8)
        try "Dentist invoice, Dr. Lee.\n\nCrown, lower molar: 1,150.00\nCleaning: 180.00\n\nPaid in full.".write(to: dir.appendingPathComponent("Dentist invoice.md"), atomically: true, encoding: .utf8)
        try "Recipe: lemon cake. 3 eggs, 200 g sugar, zest of two lemons.".write(to: dir.appendingPathComponent("recipes.txt"), atomically: true, encoding: .utf8)
    }
    static func ask(_ q: String) -> Answer { let sem = DispatchSemaphore(value: 0); var a: Answer?; Task.detached { a = await Ask.run(q, useModel: false); sem.signal() }; sem.wait(); return a! }
    static let suite = TestSuite(name: "Pipeline", cases: [
        TestCase(name: "walks folders and quotes the sentence with the answer") { t in
            let dir = URL(fileURLWithPath: Prefs.folders!.first!); try seed(dir)
            let a = ask("how much was the lease deposit")
            t.equal(a.how, .quote, "quoted (no model in tests)")
            t.check(a.text.contains("$2,400"), "answer sentence: \(a.text)")
            t.equal(a.sources.first?.passage.title, "Lease Woodland Ave", "top source")
            t.check(a.candidates >= 1, "candidates")
            let d = ask("dentist crown"); t.check(d.text.contains("1,150"), "dentist: \(d.text)")
        },
        TestCase(name: "nothing found is said plainly") { t in
            let dir = URL(fileURLWithPath: Prefs.folders!.first!); try seed(dir)
            let a = ask("submarine periscope warranty")
            t.equal(a.how, .none, "none"); t.check(a.note?.contains("Nothing") == true, "note: \(a.note ?? "")")
        },
        TestCase(name: "CLI exit codes and JSON") { t in
            let dir = URL(fileURLWithPath: Prefs.folders!.first!); try seed(dir)
            t.equal(CLI.run("lease", ["deposit", "--json"]), 0, "answered")
            t.equal(CLI.run("submarine", ["periscope"]), 1, "nothing found")
            t.equal(CLI.run("status", ["--json"]), 0, "status"); t.equal(CLI.run("version", []), 0, "version"); t.equal(CLI.run("help", []), 0, "help")
            t.equal(CLI.run("folders", []), 0, "folders")
        },
        TestCase(name: "date filter applies when walking") { t in
            let dir = URL(fileURLWithPath: Prefs.folders!.first!); try seed(dir)
            let old = dir.appendingPathComponent("Lease Woodland Ave.txt")
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-400 * 86400)], ofItemAtPath: old.path)
            let a = ask("lease deposit from last week")
            t.equal(a.how, .none, "old lease excluded: \(a.text)")
        },
        TestCase(name: "prompt for the on-device model is bounded and numbered") { t in
            let c = Candidate(url: URL(fileURLWithPath: "/tmp/x.txt"), kind: .text, modified: nil)
            let scored = (0..<10).map { i in Scored(passage: Passage(source: c, text: String(repeating: "word ", count: 600), index: i), score: 1, keyword: 1, meaning: 0) }
            let p = Answerer.prompt(Query.parse("anything"), scored: scored)
            t.check(p.count < 12_000, "bounded: \(p.count)"); t.check(p.contains("[1] x"), "numbered"); t.check(!p.contains("[10]"), "cut before ten")
            t.check(Answerer.instructions.contains("do not answer that"), "instructions say when to give up")
        },
    ])
}
