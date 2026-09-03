//  Ask for Mac — MIT licensed. See LICENSE.
import Foundation

enum RankSuite {
    static func cand(_ name: String, daysAgo: Int = 10) -> Candidate { Candidate(url: URL(fileURLWithPath: "/tmp/\(name)"), kind: Sources.kind(of: URL(fileURLWithPath: name)), modified: Date().addingTimeInterval(-Double(daysAgo) * 86400)) }
    static let suite = TestSuite(name: "Rank", cases: [
        TestCase(name: "split keeps paragraphs together and cuts walls of text") { t in
            let short = Passages.split("One.\n\nTwo.\n\nThree.", source: cand("a.txt"))
            t.equal(short.count, 1, "short doc is one passage"); t.check(short[0].text.contains("Three"), "all included")
            let wall = (0..<80).map { "Sentence number \($0) says something about the lease and the deposit." }.joined(separator: " ")
            let many = Passages.split(wall, source: cand("b.txt")); t.check(many.count >= 3, "wall cut into \(many.count) passages")
            let paras = (0..<12).map { "Paragraph \($0) " + String(repeating: "word ", count: 40) }.joined(separator: "\n\n")
            t.check(Passages.split(paras, source: cand("c.txt")).count >= 2, "paragraph groups")
        },
        TestCase(name: "keyword score favours passages with all the words") { t in
            let terms = ["dentist", "crown", "1150"]
            let a = Passages.keywordScore(terms, "The dentist charged 1150 for the crown.", title: "x")
            let b = Passages.keywordScore(terms, "The dentist sent a reminder.", title: "x")
            let c = Passages.keywordScore(terms, "Nothing here.", title: "dentist crown")
            t.check(a > b && b > c && c > 0, "ordering \(a) \(b) \(c)"); t.check(a <= 1, "bounded")
        },
        TestCase(name: "meaning score relates synonyms") { t in
            guard let q = Passages.vector("dentist invoice tooth") else { t.skip("no word embedding on this Mac"); return }
            let near = Passages.vector("The dental bill for the molar was paid.")!, far = Passages.vector("The football match ended in a draw after extra time.")!
            t.check(Passages.cosine(q, near) > Passages.cosine(q, far), "dental closer than football: \(Passages.cosine(q, near)) vs \(Passages.cosine(q, far))")
        },
        TestCase(name: "rank puts the answering passage first and caps per document") { t in
            let q = Query.parse("dentist crown cost")
            let doc1 = Passages.split("Invoice from Dr. Lee, dentist.\n\nCrown on lower molar: cost 1,150.\n\nThank you for your visit.", source: cand("dentist-invoice.pdf", daysAgo: 20))
            let doc2 = Passages.split("Grocery list: milk, eggs, bread. Crown cola.", source: cand("list.txt", daysAgo: 1))
            let doc3 = Passages.split((0..<6).map { "The dentist and the crown cost, part \($0)." }.joined(separator: "\n\n" + String(repeating: "filler ", count: 200) + "\n\n"), source: cand("long.txt"))
            let r = Passages.rank(q, passages: doc1 + doc2 + doc3, limit: 6)
            t.check(!r.isEmpty, "ranked something")
            t.check(r.first?.passage.source.url.lastPathComponent != "list.txt", "grocery list is not first")
            t.check(r.filter { $0.passage.source.url.lastPathComponent == "long.txt" }.count <= 3, "at most three from one document")
            t.check(Passages.bestSentence(q.terms, in: doc1[0].text).contains("1,150"), "best sentence: \(Passages.bestSentence(q.terms, in: doc1[0].text))")
        },
    ])
}
