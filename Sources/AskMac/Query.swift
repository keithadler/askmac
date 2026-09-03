//  Ask for Mac — MIT licensed. See LICENSE.
//
//  A question in a person's words becomes search terms, a date window and a scope. "the lease PDF
//  from last week" → terms [lease], kind pdf, since seven days ago. Nothing clever: stop words out,
//  a few date phrases recognised, file kinds recognised. The rest is left to Spotlight and ranking.

import Foundation

struct Query: Equatable {
    var text: String
    var terms: [String]          // meaningful words, lowercased
    var since: Date?
    var until: Date?
    var kinds: Set<Kind>
    var scopes: Set<Scope>
    enum Kind: String, CaseIterable { case pdf, document, spreadsheet, presentation, image, mail, note, text, code }
    enum Scope: String, CaseIterable { case files, mail, notes }

    static let stopWords: Set<String> = ["the","a","an","of","in","on","at","to","for","from","with","about","and","or","is","are","was","were","be","my","me","i","you","it","that","this","these","those","what","which","who","when","where","how","did","do","does","find","show","get","open","any","some","all","there","last","week","month","year","yesterday","today","ago","recent","recently","file","files","document","documents","email","emails","mail","message","messages","note","notes","pdf","spreadsheet","presentation","image","photo","picture","one","two","three","say","says","said","tell","told","know","sent","received","by","please","can","could","have","has","had","paid","pay","much","many"]

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Query {
        let lower = text.lowercased()
        var since: Date?; var until: Date?
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: now))! }
        if lower.contains("today") { since = calendar.startOfDay(for: now) }
        else if lower.contains("yesterday") { since = daysAgo(1); until = calendar.startOfDay(for: now) }
        else if lower.contains("this week") { since = daysAgo(7) }
        else if lower.contains("last week") || lower.contains("past week") { since = daysAgo(7) }
        else if lower.contains("this month") || lower.contains("last month") || lower.contains("past month") { since = daysAgo(31) }
        else if lower.contains("this year") || lower.contains("last year") || lower.contains("past year") { since = daysAgo(366) }
        if let m = lower.range(of: #"(\d+)\s+(day|week|month|year)s?\s+ago"#, options: .regularExpression) {
            let parts = lower[m].split(separator: " "); if let n = Int(parts[0]) {
                let unit = String(parts[1]).replacingOccurrences(of: "s", with: ""); let days = unit == "day" ? n : unit == "week" ? n * 7 : unit == "month" ? n * 31 : n * 366
                since = daysAgo(days)
            }
        }
        // Weekday names: "from Tuesday" means the most recent Tuesday.
        let weekdays = ["sunday","monday","tuesday","wednesday","thursday","friday","saturday"]
        for (i, w) in weekdays.enumerated() where lower.contains(w) {
            let today = calendar.component(.weekday, from: now) - 1
            var back = (today - i + 7) % 7; if back == 0 { back = 7 }
            since = daysAgo(back); until = daysAgo(back - 1)
        }
        // Month names, this year (or last year if the month is still ahead of us).
        let months = ["january","february","march","april","may","june","july","august","september","october","november","december"]
        for (i, m) in months.enumerated() where lower.range(of: "\\b\(m)\\b", options: .regularExpression) != nil {
            var comps = calendar.dateComponents([.year], from: now); comps.month = i + 1; comps.day = 1
            var start = calendar.date(from: comps)!
            if start > now { start = calendar.date(byAdding: .year, value: -1, to: start)! }
            since = start; until = calendar.date(byAdding: .month, value: 1, to: start)
        }
        if let m = lower.range(of: #"\b(20\d\d)\b"#, options: .regularExpression), until == nil || since == nil {
            let year = Int(lower[m])!; var c = DateComponents(); c.year = year; c.month = 1; c.day = 1
            if let s = calendar.date(from: c) { since = s; until = calendar.date(byAdding: .year, value: 1, to: s) }
        }
        var kinds = Set<Kind>()
        if lower.contains("pdf") { kinds.insert(.pdf) }
        if lower.contains("spreadsheet") || lower.contains("excel") || lower.contains("numbers file") { kinds.insert(.spreadsheet) }
        if lower.contains("presentation") || lower.contains("keynote") || lower.contains("slides") { kinds.insert(.presentation) }
        if lower.contains("word doc") || lower.contains("docx") || lower.contains(" pages ") { kinds.insert(.document) }
        if lower.contains("photo") || lower.contains("picture") || lower.contains("screenshot") || lower.contains("image") { kinds.insert(.image) }
        if lower.contains("source code") || lower.contains(" code") || lower.contains("script") || lower.contains("swift file") { kinds.insert(.code) }
        var scopes = Set<Scope>()
        if lower.contains("email") || lower.contains("e-mail") || lower.contains(" mail") || lower.hasPrefix("mail") || lower.contains("message") { scopes.insert(.mail) }
        if lower.range(of: #"\bnotes?\b"#, options: .regularExpression) != nil { scopes.insert(.notes) }
        if scopes.isEmpty || lower.contains("file") || lower.contains("pdf") || lower.contains("document") { scopes.insert(.files) }
        let words = lower.replacingOccurrences(of: "[^a-z0-9$€£%.'@-]+", with: " ", options: .regularExpression)
            .split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".'-")) }
            .filter { !$0.isEmpty && !stopWords.contains($0) && !weekdays.contains($0) && !months.contains($0) && $0.count > 1 }
        var seen = Set<String>(); let terms = words.filter { seen.insert($0).inserted }
        return Query(text: text, terms: terms, since: since, until: until, kinds: kinds, scopes: scopes)
    }
}
