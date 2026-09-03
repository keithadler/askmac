//  Ask for Mac — MIT licensed. See LICENSE.
//
//  The command-line face. Exit codes: 0 answered, 1 nothing found, 2 problem, 64 usage error.

import Foundation
import AppKit

enum CLI {
    static let usage = """
    askmac — ask your files a question, answered on this Mac (command-line face)

    USAGE
      askmac "<question>" [--json] [--quote] [--limit N] [--in <folder>]
                                                             answer with sources; --quote skips the model; --in looks only there
      askmac status [--json]                                 folders searched, Spotlight, Apple Intelligence
      askmac folders [add|remove <path>]                     which folders are searched
      askmac skip [add|remove <path>]                        folders inside those that are never searched
      askmac screenshots <dir> [--announce]                  render windows and promo cards from demo data
      askmac selftest [--filter S] [--list] [--json]
      askmac help | version

    Questions are plain words: "lease deposit", "what did the dentist invoice say in March",
    "email from Sam about the roof last week". Dates, months and weekdays are understood.
    Set ASKMAC_HOME to isolate settings (tests do); ASKMAC_WALK=1 skips Spotlight and reads folders directly.
    """

    static var version: String {
        if Bundle.main.bundleIdentifier == "com.keithadler.askmac", let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let b = Bundle(url: url), b.bundleIdentifier == "com.keithadler.askmac", let v = b.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
            url = url.deletingLastPathComponent()
        }
        return "dev"
    }

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let h = env["ASKMAC_HOME"], !h.isEmpty { Prefs.defaults = UserDefaults(suiteName: "com.keithadler.askmac.test")!; Prefs.folders = [h] }
        if env["ASKMAC_WALK"] == "1" { Ask.useSpotlight = false }
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first, !cmd.hasPrefix("-psn") else { return }
        exit(run(cmd, Array(args.dropFirst())))
    }

    static func flag(_ n: String, _ a: [String]) -> Bool { a.contains(n) }
    static func value(_ n: String, _ a: [String]) -> String? { guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }; return a[i + 1] }
    static func positional(_ a: [String]) -> [String] {
        var out: [String] = []; var skip = false
        for x in a { if skip { skip = false; continue }; if ["--filter", "--limit", "--in"].contains(x) { skip = true; continue }; if x.hasPrefix("--") { continue }; out.append(x) }
        return out
    }
    static var quiet = false
    static func out(_ s: String) { if !quiet { print(s) } }
    static func err(_ s: String) { if !quiet { fputs(s, stderr) } }
    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    static func sourceDict(_ s: Scored) -> [String: Any] {
        var d: [String: Any] = ["file": s.passage.source.url.path, "title": s.passage.title, "page": s.passage.page ?? 0, "kind": s.passage.source.kind.rawValue, "score": (s.score * 1000).rounded() / 1000, "passage": s.passage.text]
        if let m = s.passage.source.modified { d["modified"] = ISO8601DateFormatter().string(from: m) }
        return d
    }

    static func run(_ cmd: String, _ args: [String]) -> Int32 {
        let js = flag("--json", args)
        let pos = positional(args)
        switch cmd {
        case "help", "--help", "-h": out(usage); return 0
        case "version", "--version": out("askmac \(version)"); return 0
        case "status":
            let m = Answerer.modelStatus()
            let d: [String: Any] = ["folders": Sources.folders.map(\.path), "skipped": Prefs.skipped, "spotlightOff": Sources.spotlightOff() ?? "", "mail": Prefs.includeMail && FileManager.default.isReadableFile(atPath: Sources.mailFolder.path), "appleIntelligence": m.available, "modelNote": m.why, "spotlight": Ask.useSpotlight, "version": version]
            if js { out(json(d)) } else {
                out("Folders: " + Sources.folders.map { $0.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") }.joined(separator: ", "))
                out("Mail: " + ((d["mail"] as? Bool) == true ? "included" : "not readable (Full Disk Access) or turned off"))
                out(m.why)
                if let off = Sources.spotlightOff() { out("Spotlight indexing is off for \(off); files there cannot be found.") }
            }
            return 0
        case "folders":
            if pos.first == "add", pos.count > 1 { var f = Prefs.folders ?? Sources.folders.map(\.path); f.append(URL(fileURLWithPath: pos[1]).standardizedFileURL.path); Prefs.folders = f }
            if pos.first == "remove", pos.count > 1 { Prefs.folders = (Prefs.folders ?? Sources.folders.map(\.path)).filter { $0 != URL(fileURLWithPath: pos[1]).standardizedFileURL.path } }
            for f in Sources.folders { out(f.path) }
            return 0
        case "skip":
            if pos.first == "add", pos.count > 1 { Prefs.skipped = Array(Set(Prefs.skipped + [URL(fileURLWithPath: pos[1]).standardizedFileURL.path])).sorted() }
            if pos.first == "remove", pos.count > 1 { Prefs.skipped = Prefs.skipped.filter { $0 != URL(fileURLWithPath: pos[1]).standardizedFileURL.path } }
            for f in Prefs.skipped { out(f) }
            if Prefs.skipped.isEmpty { out("Nothing skipped beyond the usual (.git, node_modules, caches, Trash).") }
            return 0
        case "screenshots":
            guard let dir = pos.first else { err("askmac screenshots <dir>\n"); return 64 }
            do { let files = try MainActor.assumeIsolated { try Screenshots.render(to: URL(fileURLWithPath: dir), announce: flag("--announce", args)) }; for f in files { out(f.path) }; return 0 }
            catch { err("screenshots failed: \(error)\n"); return 2 }
        case "selftest":
            if flag("--list", args) { TestKit.list(); return 0 }
            let results = MainActor.assumeIsolated { TestKit.run(filter: value("--filter", args)) }
            return TestKit.report(results, json: js)
        default:
            // Anything else is the question.
            let question = ([cmd] + pos).joined(separator: " ")
            guard question.count > 2 else { err(usage + "\n"); return 64 }
            let limit = Int(value("--limit", args) ?? "") ?? 8
            if let folder = value("--in", args) { Sources.scopeOverride = URL(fileURLWithPath: folder).standardizedFileURL }
            let sem = DispatchSemaphore(value: 0); var answer: Answer?
            Task { answer = await Ask.run(question, useModel: !flag("--quote", args) && Prefs.useModel, limit: limit); sem.signal() }
            sem.wait()
            guard let a = answer else { return 2 }
            if js { out(json(["question": question, "answer": a.text, "how": a.how.rawValue, "note": a.note ?? "", "candidates": a.candidates, "seconds": (a.elapsed * 100).rounded() / 100, "phases": a.phases, "sources": a.sources.map(sourceDict)])) }
            else {
                if a.how == .none { out(a.note ?? "Nothing found."); return 1 }
                out(a.how == .quote ? "“\(a.text)”" : a.text)
                out(a.declined ? "\nClosest matches:" : "")
                var seen = Set<URL>()
                for (i, s) in a.sources.enumerated() where seen.insert(s.passage.source.url).inserted || a.how == .model {
                    let when = s.passage.source.modified.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
                    out("[\(i + 1)] \(s.passage.title)\(s.passage.page.map { ", page \($0)" } ?? "")\(when)\n    \(s.passage.source.noteId != nil ? "Apple Notes" : s.passage.source.url.path)")
                }
                out(String(format: "\n%d files considered, %.1f s%@", a.candidates, a.elapsed, a.how == .quote ? ", quoted (no on-device model)" : ""))
            }
            return a.how == .none ? 1 : 0
        }
    }
}
