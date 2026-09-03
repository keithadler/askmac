//  Ask for Mac — MIT licensed. See LICENSE.
//
//  Ranking. A document becomes passages of a few hundred words; each passage gets a keyword score
//  (how many of the question's words it contains, how often) and a meaning score (the same
//  on-device word embeddings Clip for Mac uses, averaged). The best passages, with their source,
//  are what the answer is built from. Everything here is pure and testable.

import Foundation
import NaturalLanguage

struct Passage: Hashable {
    let source: Candidate
    let text: String
    let index: Int
    var page: Int? = nil       // PDFs: 1-based page the passage starts on
    var title: String { source.title ?? source.url.deletingPathExtension().lastPathComponent }
}

struct Scored: Hashable { let passage: Passage; let score: Double; let keyword: Double; let meaning: Double }

enum Passages {
    static let targetWords = 180

    /// PDFs page by page, so a source can say "page 12".
    static func split(pages: [String], source: Candidate) -> [Passage] {
        var out: [Passage] = []
        for (i, page) in pages.enumerated() {
            for p in split(page, source: source) { out.append(Passage(source: source, text: p.text, index: out.count, page: i + 1)) }
        }
        return out
    }

    static func split(_ text: String, source: Candidate) -> [Passage] {
        let paragraphs = text.components(separatedBy: CharacterSet.newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var out: [Passage] = []; var current: [String] = []; var words = 0
        func flush() { if !current.isEmpty { out.append(Passage(source: source, text: current.joined(separator: "\n"), index: out.count)); current = []; words = 0 } }
        for p in paragraphs {
            let w = p.split(separator: " ").count
            if w > targetWords * 2 {   // a wall of text: cut by sentences
                flush()
                var chunk: [String] = []; var cw = 0
                for s in sentences(p) { chunk.append(s); cw += s.split(separator: " ").count; if cw >= targetWords { out.append(Passage(source: source, text: chunk.joined(separator: " "), index: out.count)); chunk = []; cw = 0 } }
                if !chunk.isEmpty { out.append(Passage(source: source, text: chunk.joined(separator: " "), index: out.count)) }
                continue
            }
            if words + w > targetWords, !current.isEmpty { flush() }
            current.append(p); words += w
        }
        flush()
        return out
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        let tok = NLTokenizer(unit: .sentence); tok.string = text
        tok.enumerateTokens(in: text.startIndex..<text.endIndex) { r, _ in let s = text[r].trimmingCharacters(in: .whitespacesAndNewlines); if !s.isEmpty { out.append(s) }; return true }
        return out.isEmpty ? [text] : out
    }

    // Meaning: averaged word vectors. Sentence embeddings scored nonsense highly in Clip; word averages behave.
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)
    static func vector(_ text: String) -> [Double]? {
        guard let emb = embedding else { return nil }
        var sum = [Double](repeating: 0, count: emb.dimension); var n = 0
        for w in text.lowercased().split(whereSeparator: { !$0.isLetter }).prefix(400) where w.count > 2 && !Query.stopWords.contains(String(w)) {
            if let v = emb.vector(for: String(w)) { for i in 0..<v.count { sum[i] += v[i] }; n += 1 }
        }
        guard n > 0 else { return nil }
        return sum.map { $0 / Double(n) }
    }
    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }

    static func keywordScore(_ terms: [String], _ text: String, title: String) -> Double {
        guard !terms.isEmpty else { return 0 }
        let lower = text.lowercased(), t = title.lowercased()
        var hits = 0.0
        for term in terms {
            let count = lower.components(separatedBy: term).count - 1
            if count > 0 { hits += 1 + min(Double(count) / 4, 1) }       // presence matters most, repetition a little
            else if t.contains(term) { hits += 0.5 }
        }
        return hits / (Double(terms.count) * 2)
    }

    static func rank(_ q: Query, passages: [Passage], limit: Int = 8) -> [Scored] {
        let qv = vector(q.terms.joined(separator: " ")) ?? vector(q.text)
        // Keywords first for everything, then meaning only for the best hundred: word vectors over
        // thousands of passages were most of the wait.
        let keyed = passages.map { ($0, keywordScore(q.terms, $0.text, title: $0.title)) }
        let shortlist = Set(keyed.sorted { $0.1 > $1.1 }.prefix(100).map { $0.0 })
        var out: [Scored] = []
        for (p, k) in keyed {
            var m = 0.0
            if shortlist.contains(p), let qv, let pv = vector(p.text) { m = max(0, cosine(qv, pv)) }
            let recency: Double = { guard let d = p.source.modified else { return 0 }; let days = Date().timeIntervalSince(d) / 86400; return days < 30 ? 0.05 : days < 365 ? 0.02 : 0 }()
            let score = k * 0.65 + m * 0.35 + recency
            if k > 0 || m > 0.45 { out.append(Scored(passage: p, score: score, keyword: k, meaning: m)) }
        }
        out.sort { $0.score > $1.score }
        // At most three passages per document so one long file cannot crowd out the rest.
        var perDoc: [URL: Int] = [:]; var picked: [Scored] = []
        for s in out { let n = perDoc[s.passage.source.url, default: 0]; if n < 3 { picked.append(s); perDoc[s.passage.source.url] = n + 1 }; if picked.count >= limit { break } }
        return picked
    }

    /// The sentence in a passage that carries the most of the question.
    static func bestSentence(_ terms: [String], in passage: String) -> String {
        var best = ""; var bestScore = -1.0
        for s in sentences(passage) {
            // Facts live in sentences with amounts, dates and numbers; headings rarely answer anything.
            let hasAmount = s.range(of: #"[$€£]\s?\d|\d[,.]\d{2}|\d+\s?%|\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b"#, options: .regularExpression) != nil
            let hasDigit = s.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            let sc = keywordScore(terms, s, title: "") + (hasAmount ? 0.25 : hasDigit ? 0.05 : 0) - Double(s.count) / 4000
            if sc > bestScore { bestScore = sc; best = s }
        }
        return best
    }
}
