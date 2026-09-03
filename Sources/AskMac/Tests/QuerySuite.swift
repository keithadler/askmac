//  Ask for Mac — MIT licensed. See LICENSE.
import Foundation

enum QuerySuite {
    static let now: Date = { var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 3; c.hour = 12; return Calendar.current.date(from: c)! }()   // a Thursday
    static let suite = TestSuite(name: "Query", cases: [
        TestCase(name: "terms drop stop words and keep the meat") { t in
            let q = Query.parse("what did the dentist invoice say about the crown", now: now)
            t.equal(q.terms, ["dentist", "invoice", "crown"], "terms")
            t.check(q.since == nil, "no date"); t.equal(q.scopes, [.files], "files by default")
        },
        TestCase(name: "dates: last week, yesterday, weekdays, months, years") { t in
            let cal = Calendar.current
            t.equal(Query.parse("lease from last week", now: now).since, cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)), "last week")
            let y = Query.parse("email yesterday about the roof", now: now); t.equal(y.since, cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)), "yesterday since"); t.equal(y.until, cal.startOfDay(for: now), "yesterday until")
            let tue = Query.parse("meeting notes from Tuesday", now: now)
            t.equal(tue.since, cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now)), "tuesday is two days before a thursday"); t.equal(tue.terms, ["meeting"], "weekday not a term")
            let mar = Query.parse("dentist invoice in March", now: now)
            t.equal(cal.component(.month, from: mar.since!), 3, "march"); t.equal(cal.component(.year, from: mar.since!), 2026, "this year's march")
            let dec = Query.parse("bonus letter december", now: now); t.equal(cal.component(.year, from: dec.since!), 2025, "december still ahead means last year")
            let yr = Query.parse("tax return 2025 total", now: now); t.equal(cal.component(.year, from: yr.since!), 2025, "year"); t.equal(yr.terms, ["tax", "return", "2025", "total"], "year kept as a term too")
            t.equal(Query.parse("3 weeks ago receipt", now: now).since, cal.date(byAdding: .day, value: -21, to: cal.startOfDay(for: now)), "n weeks ago")
        },
        TestCase(name: "kinds and scopes") { t in
            let q = Query.parse("the lease pdf", now: now); t.equal(q.kinds, [.pdf], "pdf kind"); t.equal(q.terms, ["lease"], "pdf not a term")
            let m = Query.parse("email from Sam about the roof", now: now); t.check(m.scopes.contains(.mail), "mail scope"); t.check(!m.scopes.contains(.files), "mail only"); t.equal(m.terms, ["sam", "roof"], "terms")
            let n = Query.parse("my notes on the garden", now: now); t.check(n.scopes.contains(.notes), "notes scope")
            let s = Query.parse("spreadsheet with the budget", now: now); t.equal(s.kinds, [.spreadsheet], "spreadsheet")
        },
        TestCase(name: "spotlight query text") { t in
            let q = Query.parse("lease deposit last week", now: now)
            let s = Sources.spotlightQuery(q, mail: false)
            t.check(s.contains("kMDItemTextContent == \"lease*\"cdw"), "content clause"); t.check(s.contains("deposit*"), "second term")
            t.check(s.contains("kMDItemContentModificationDate >= $time.iso("), "date clause"); t.check(s.contains("!= \"com.apple.mail.emlx\""), "files exclude mail")
            t.check(Sources.spotlightQuery(q, mail: true).contains("== \"com.apple.mail.emlx\""), "mail query")
            let root = URL(fileURLWithPath: Prefs.folders!.first!)
            t.equal(Sources.displayPath(root.appendingPathComponent("Taxes/2025")), root.lastPathComponent + "/Taxes/2025", "display path relative to searched folder")
            t.check(Sources.displayPath(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Elsewhere")).hasPrefix("~/"), "home shortened")
            t.equal(Sources.kind(of: URL(fileURLWithPath: "/a/b.PDF")), .pdf, "kind by extension"); t.equal(Sources.kind(of: URL(fileURLWithPath: "/a/b.emlx")), .mail, "mail kind")
        },
    ])
}
