//  Ask for Mac — MIT licensed. See LICENSE.
//
//  Where candidates come from. The Mac already has a full-text index of every file and mail
//  message, Spotlight, so there is no second index here: ask it for files containing the words,
//  then read those files ourselves. When Spotlight is off for a folder, walk the folder instead.

import Foundation

struct Candidate: Hashable {
    let url: URL
    let kind: Query.Kind
    let modified: Date?
    var text: String? = nil       // already-known content (Apple Notes); files are read on demand
    var noteId: String? = nil
    var isMail: Bool { kind == .mail }
}

enum Sources {
    /// Folders searched by default. Settings can change this.
    static var folders: [URL] {
        if let saved = Prefs.folders, !saved.isEmpty { return saved.map { URL(fileURLWithPath: $0) } }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var out = ["Documents", "Desktop", "Downloads"].map { home.appendingPathComponent($0) }
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: icloud.path) { out.append(icloud) }
        return out
    }
    /// "Documents/Taxes" rather than a full path: relative to the searched folder when inside one, else ~.
    static func displayPath(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().path     // /var vs /private/var
        for f in folders.map({ $0.resolvingSymlinksInPath() }) where path.hasPrefix(f.path) {
            let rest = path.dropFirst(f.path.count)
            return f.lastPathComponent + (rest.isEmpty ? "" : String(rest))
        }
        if url.path.hasPrefix(mailFolder.path) { return "Mail" }
        if url.path.hasPrefix("/Notes/") { return "Notes" }
        return url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
    static var mailFolder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail") }

    /// Runs mdfind. Tests replace this.
    static var mdfind: ([String]) -> [String] = { args in
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind"); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// Spotlight query for the terms: every term must appear in the content or the name.
    static func spotlightQuery(_ q: Query, mail: Bool) -> String {
        var parts: [String] = []
        for t in q.terms.prefix(6) {
            let esc = t.replacingOccurrences(of: "\"", with: "")
            // Word-prefix matching ("cdw") uses Spotlight's word index; substring matching walked it and took seconds.
            parts.append("(kMDItemTextContent == \"\(esc)*\"cdw || kMDItemDisplayName == \"\(esc)*\"cdw || kMDItemTitle == \"\(esc)*\"cdw || kMDItemSubject == \"\(esc)*\"cdw || kMDItemAuthors == \"\(esc)*\"cdw)")
        }
        if mail { parts.append("kMDItemContentType == \"com.apple.mail.emlx\"") }
        else { parts.append("kMDItemContentType != \"com.apple.mail.emlx\"") }
        if let s = q.since { parts.append("kMDItemContentModificationDate >= $time.iso(\(iso(s)))") }
        if let u = q.until { parts.append("kMDItemContentModificationDate < $time.iso(\(iso(u)))") }
        return parts.joined(separator: " && ")
    }
    static func iso(_ d: Date) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.string(from: d) }

    static func kind(of url: URL) -> Query.Kind {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "emlx", "eml": return .mail
        case "doc", "docx", "rtf", "rtfd", "pages", "odt": return .document
        case "xls", "xlsx", "numbers", "csv", "tsv": return .spreadsheet
        case "ppt", "pptx", "key": return .presentation
        case "png", "jpg", "jpeg", "heic", "gif", "tiff", "webp": return .image
        case "swift", "py", "js", "ts", "tsx", "jsx", "rb", "go", "c", "h", "m", "mm", "java", "kt", "rs", "sh", "zsh", "css", "scss", "sql", "yml", "yaml", "toml", "lock", "plist", "xcconfig", "pbxproj", "gradle", "php", "cs":
            return .code
        default: return .text
        }
    }
    /// Folders nobody means when they ask about "my files".
    static let skippedPathParts = ["/.git/", "/node_modules/", "/.build/", "/DerivedData/", "/Library/Caches/", "/.Trash/", "/Pods/", "/vendor/", "/dist/", "/target/"]
    static func skipped(_ url: URL) -> Bool { skippedPathParts.contains { url.path.contains($0) } }

    /// Images by name and date only: Spotlight has no text for most of them; OCR supplies it.
    static func imageQuery(_ q: Query) -> String {
        var parts = ["kMDItemContentTypeTree == \"public.image\""]
        let named = q.terms.filter { $0 != "screenshot" }.prefix(4).map { "kMDItemDisplayName == \"*\($0)*\"cd" }
        if !named.isEmpty { parts.append("(" + named.joined(separator: " || ") + ")") }
        if let s = q.since { parts.append("kMDItemContentModificationDate >= $time.iso(\(iso(s)))") }
        if let u = q.until { parts.append("kMDItemContentModificationDate < $time.iso(\(iso(u)))") }
        return parts.joined(separator: " && ")
    }

    static func candidates(for q: Query, limit: Int = 60) -> [Candidate] {
        var filePaths: [String] = [], mailPaths: [String] = [], imagePaths: [String] = []
        var notes: [NoteHit] = []
        let group = DispatchGroup()
        if q.kinds.contains(.image) {
            group.enter(); DispatchQueue.global().async {
                var args: [String] = []; for f in folders { args += ["-onlyin", f.path] }
                var r = mdfind(args + [imageQuery(q)])
                if r.isEmpty, q.since == nil {   // no name match: the newest screenshots are the likely answer
                    var recent = q; recent.since = Date().addingTimeInterval(-30 * 86400); recent.terms = []; r = mdfind(args + [imageQuery(recent)])
                }
                imagePaths = Array(r.prefix(20)); group.leave()
            }
        }
        if q.scopes.contains(.notes), Prefs.includeNotes {
            group.enter(); DispatchQueue.global().async { notes = Notes.search(q.terms); group.leave() }
        }
        if q.scopes.contains(.files) {
            group.enter(); DispatchQueue.global().async {
                var args: [String] = []
                for f in folders { args += ["-onlyin", f.path] }
                var results = mdfind(args + [spotlightQuery(q, mail: false)])
                if results.isEmpty, q.terms.count > 1 {     // loosen: the first two terms only
                    var loose = q; loose.terms = Array(q.terms.prefix(2)); results = mdfind(args + [spotlightQuery(loose, mail: false)])
                }
                filePaths = results; group.leave()
            }
        }
        if q.scopes.contains(.mail), Prefs.includeMail, FileManager.default.isReadableFile(atPath: mailFolder.path) {
            group.enter(); DispatchQueue.global().async { mailPaths = mdfind(["-onlyin", mailFolder.path, spotlightQuery(q, mail: true)]); group.leave() }
        }
        group.wait()
        let paths = filePaths + mailPaths + imagePaths
        var seen = Set<String>()
        var out: [Candidate] = []
        for p in paths where seen.insert(p).inserted && !p.isEmpty {
            let url = URL(fileURLWithPath: p)
            let k = kind(of: url)
            if skipped(url) { continue }
            if !q.kinds.isEmpty, !q.kinds.contains(k), k != .mail { continue }
            if k == .image, !q.kinds.contains(.image) { continue }   // images only when asked for; OCR is slow
            if k == .code, !q.kinds.contains(.code) { continue }   // source code answers nothing about a lease
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            out.append(Candidate(url: url, kind: k, modified: mod))
        }
        for n in notes {
            var c = Candidate(url: URL(fileURLWithPath: "/Notes/\(n.name.replacingOccurrences(of: "/", with: "-")).note"), kind: .note, modified: n.modified)
            c.text = n.name + "\n\n" + n.body; c.noteId = n.id; out.append(c)
        }
        // Newest first among candidates; ranking will reorder by relevance.
        return Array(out.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }.prefix(limit))
    }

    /// Fallback and tests: walk folders and keep files whose text contains every term.
    static func walk(_ q: Query, folders: [URL], limit: Int = 60) -> [Candidate] {
        var out: [Candidate] = []
        for folder in folders {
            guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let k = kind(of: url); if k == .image || skipped(url) { continue }
                if k == .code, !q.kinds.contains(.code) { continue }
                if !q.kinds.isEmpty, !q.kinds.contains(k) { continue }
                let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if let s = q.since, let m = mod, m < s { continue }
                if let u = q.until, let m = mod, m >= u { continue }
                guard let text = Extract.text(from: url)?.lowercased() else { continue }
                let name = url.lastPathComponent.lowercased()
                if q.terms.allSatisfy({ text.contains($0) || name.contains($0) }) { out.append(Candidate(url: url, kind: k, modified: mod)) }
                if out.count >= limit { return out }
            }
        }
        return out
    }
}
