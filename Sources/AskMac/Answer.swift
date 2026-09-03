//  Ask for Mac — MIT licensed. See LICENSE.
//
//  From ranked passages to an answer a person can check. Two ways, both on the Mac:
//  - On macOS 26 with Apple Intelligence, Apple's on-device language model writes two or three
//    sentences from the passages, with [1] [2] citations, and is told to say so when they do not
//    contain the answer.
//  - Everywhere else (and when the model is unavailable or asked to stay off), the answer is the
//    best-matching sentence quoted from the top file. Less fluent, never invented.
//  Every answer lists its sources; nothing here goes on the network.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct Answer {
    enum How: String { case model, quote, none }
    var text: String
    var how: How
    var sources: [Scored]
    var elapsed: TimeInterval
    var candidates: Int
    var note: String?
    var phases: [String: Double] = [:]     // find, read, rank, answer, in seconds
}

enum Answerer {
    /// Whether Apple's on-device model can be used right now, and if not, why not in one line.
    static func modelStatus() -> (available: Bool, why: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return (true, "Apple Intelligence is on; answers are written on this Mac.")
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return (false, "This Mac cannot run Apple Intelligence; answers are quoted from your files instead.")
                case .appleIntelligenceNotEnabled: return (false, "Apple Intelligence is off in System Settings; answers are quoted from your files instead.")
                case .modelNotReady: return (false, "Apple Intelligence is still downloading its model; answers are quoted from your files until it is ready.")
                @unknown default: return (false, "Apple Intelligence is unavailable; answers are quoted from your files instead.")
                }
            }
        }
        #endif
        return (false, "Written answers need macOS 26 with Apple Intelligence; on this Mac answers are quoted from your files.")
    }

    static func answer(_ q: Query, scored: [Scored], candidates: Int, useModel: Bool, started: Date, onPartial: ((String) -> Void)? = nil) async -> Answer {
        guard let top = scored.first else {
            return Answer(text: "", how: .none, sources: [], elapsed: Date().timeIntervalSince(started), candidates: candidates,
                          note: candidates == 0 ? "Nothing on this Mac matches those words." : "Files matched the words, but no passage answered the question.")
        }
        if useModel, modelStatus().available, let written = await writeWithModel(q, scored: scored, onPartial: onPartial) {
            return Answer(text: written, how: .model, sources: scored, elapsed: Date().timeIntervalSince(started), candidates: candidates, note: nil)
        }
        let sentence = Passages.bestSentence(q.terms, in: top.passage.text)
        return Answer(text: sentence, how: .quote, sources: scored, elapsed: Date().timeIntervalSince(started), candidates: candidates, note: nil)
    }

    static func prompt(_ q: Query, scored: [Scored]) -> String {
        var p = "Question: \(q.text)\n\nPassages from the person's own files, numbered:\n"
        var budget = 9000   // characters; the on-device model's window is small
        for (i, s) in scored.enumerated() {
            let t = s.passage.text.count > 1500 ? String(s.passage.text.prefix(1500)) : s.passage.text
            if budget - t.count < 0 { break }
            budget -= t.count
            p += "\n[\(i + 1)] \(s.passage.title)\(s.passage.source.modified.map { " (\($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""):\n\(t)\n"
        }
        return p
    }
    static let instructions = "You answer questions using only the numbered passages provided, which come from the person's own files. Answer in at most three plain sentences. After each fact, cite the passage number in square brackets like [1]. If the passages do not contain the answer, say exactly: The files I found do not answer that. Never invent names, numbers or dates."

    static func writeWithModel(_ q: Query, scored: [Scored], onPartial: ((String) -> Void)? = nil) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: instructions)
                var last = ""
                for try await partial in session.streamResponse(to: prompt(q, scored: scored)) {
                    last = partial.content; onPartial?(last)
                }
                let text = last.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch { return nil }
        }
        #endif
        return nil
    }
}

/// The whole pipeline in one call, used by the window and the command line alike.
enum Ask {
    static var useSpotlight = true
    static func run(_ text: String, useModel: Bool = Prefs.useModel, limit: Int = 8, progress: ((String) -> Void)? = nil, onPartial: ((String) -> Void)? = nil) async -> Answer {
        let started = Date(); var phases: [String: Double] = [:]; var mark = Date()
        progress?("Finding files…")
        func lap(_ name: String) { phases[name] = (Date().timeIntervalSince(mark) * 100).rounded() / 100; mark = Date() }
        let q = Query.parse(text)
        var cands = useSpotlight ? Sources.candidates(for: q) : Sources.walk(q, folders: Sources.folders)
        if cands.isEmpty, useSpotlight, !q.terms.isEmpty { cands = Sources.walk(q, folders: Sources.folders, limit: 20) }   // Spotlight off or behind
        lap("find")
        let toRead = Array(cands.prefix(40))
        progress?(toRead.isEmpty ? "Nothing matched." : "Reading \(toRead.count) \(toRead.count == 1 ? "file" : "files")…")
        // Read candidates in parallel; each file's text lives only until it is split into passages.
        var perFile = [[Passage]](repeating: [], count: toRead.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: toRead.count) { i in
            autoreleasepool {
                if let t = toRead[i].text ?? Extract.text(from: toRead[i].url) { let p = Passages.split(t, source: toRead[i]); lock.lock(); perFile[i] = p; lock.unlock() }
            }
        }
        let passages = perFile.flatMap { $0 }
        lap("read")
        progress?("Ranking \(passages.count) passages…")
        let scored = Passages.rank(q, passages: passages, limit: limit)
        lap("rank")
        progress?(useModel && Answerer.modelStatus().available && !scored.isEmpty ? "Writing the answer…" : "Picking the sentence…")
        var a = await Answerer.answer(q, scored: scored, candidates: cands.count, useModel: useModel, started: started, onPartial: onPartial)
        lap("answer"); a.phases = phases
        return a
    }
}

enum Prefs {
    static var defaults = UserDefaults.standard
    static var folders: [String]? { get { defaults.stringArray(forKey: "folders") } set { defaults.set(newValue, forKey: "folders") } }
    static var useModel: Bool { get { defaults.object(forKey: "useModel") as? Bool ?? true } set { defaults.set(newValue, forKey: "useModel") } }
    static var includeMail: Bool { get { defaults.object(forKey: "includeMail") as? Bool ?? true } set { defaults.set(newValue, forKey: "includeMail") } }
    static var includeNotes: Bool { get { defaults.object(forKey: "includeNotes") as? Bool ?? true } set { defaults.set(newValue, forKey: "includeNotes") } }
    static var hotkey: Bool { get { defaults.object(forKey: "hotkey") as? Bool ?? true } set { defaults.set(newValue, forKey: "hotkey") } }
    static var menuBar: Bool { get { defaults.object(forKey: "menuBar") as? Bool ?? true } set { defaults.set(newValue, forKey: "menuBar") } }
    static var keepHistory: Bool { get { defaults.object(forKey: "keepHistory") as? Bool ?? true } set { defaults.set(newValue, forKey: "keepHistory") } }
    static var history: [String] { get { defaults.stringArray(forKey: "history") ?? [] } set { defaults.set(Array(newValue.suffix(50)), forKey: "history") } }
}
