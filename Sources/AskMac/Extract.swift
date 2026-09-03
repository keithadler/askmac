//  Ask for Mac — MIT licensed. See LICENSE.
//
//  Plain text out of the files people actually have: PDF, Word, RTF, HTML, plain text and Markdown,
//  spreadsheets as CSV, and Mail's .emlx messages. Nothing is kept; the text lives only while a
//  question is being answered.

import Foundation
import AppKit
import PDFKit

enum Extract {
    static let maxBytes = 12_000_000
    static let maxChars = 400_000

    /// Text already read this session, keyed by path and modification date, so a follow-up does not
    /// read the same forty files again. Lives in memory only; capped so it cannot grow without bound.
    private static var cache: [String: (pages: [String]?, text: String?)] = [:]
    private static var cacheChars = 0
    static let cacheLimit = 40_000_000
    static var reads = 0     // tests count real reads
    private static let cacheLock = NSLock()
    static func cacheKey(_ url: URL) -> String {
        let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(m)"
    }
    static func cached(_ url: URL, compute: () -> (pages: [String]?, text: String?)) -> (pages: [String]?, text: String?) {
        let key = cacheKey(url)
        cacheLock.lock(); if let hit = cache[key] { cacheLock.unlock(); return hit }; cacheLock.unlock()
        let v = compute()
        cacheLock.lock()
        reads += 1
        let size = (v.text?.count ?? 0) + (v.pages?.reduce(0) { $0 + $1.count } ?? 0)
        if cacheChars + size > cacheLimit { cache.removeAll(); cacheChars = 0 }
        cache[key] = v; cacheChars += size
        cacheLock.unlock()
        return v
    }
    static func clearCache() { cacheLock.lock(); cache.removeAll(); cacheChars = 0; cacheLock.unlock() }

    struct Mail { var subject: String; var from: String; var to: String; var date: Date?; var body: String }

    static func text(from url: URL) -> String? {
        cached(url) { (nil, textUncached(from: url)) }.text
    }
    static func textUncached(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if ["numbers", "pages", "key"].contains(ext) { return iWork(url).flatMap { $0.isEmpty ? nil : $0 } }   // packages have no file size
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize), size <= maxBytes else { return nil }
        var out: String?
        switch ext {
        case "pdf": out = pdf(url)
        case "xlsx": out = zipXML(url, members: ["xl/sharedStrings.xml"], also: "xl/worksheets/sheet1.xml")
        case "pptx": out = zipXML(url, members: [], also: "ppt/slides/slide*.xml")
        case "emlx", "eml": out = mail(from: url).map { "\($0.subject)\nFrom: \($0.from)\nTo: \($0.to)\n\n\($0.body)" }
        case "rtf", "rtfd", "doc", "docx", "html", "htm", "odt", "webarchive":
            out = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        case "csv", "tsv", "txt", "md", "markdown", "text", "json", "xml", "yaml", "yml", "log", "swift", "py", "js", "ts", "sh", "rb", "go", "c", "h", "m", "java", "tex", "org", "ics", "vcf", "eml2":
            out = plain(url)
        case "png", "jpg", "jpeg", "heic", "tiff", "gif", "webp", "bmp": out = OCR.recognize(url)
        case "numbers", "pages", "key": out = iWork(url)
        default:
            // Unknown extension: try it as text when it looks like text.
            if let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.prefix(4096).allSatisfy({ $0 == 9 || $0 == 10 || $0 == 13 || $0 >= 32 }) { out = String(decoding: d, as: UTF8.self) }
        }
        guard var s = out?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.count > maxChars { s = String(s.prefix(maxChars)) }
        return s
    }

    /// Page by page, stopping once there is enough: PDFDocument.string on a 400-page manual took seconds.
    static func pdf(_ url: URL) -> String? { pdfPagesUncached(url)?.joined(separator: "\n") }
    static func pdfPages(_ url: URL) -> [String]? { cached(url) { (pdfPagesUncached(url), nil) }.pages }
    static func pdfPagesUncached(_ url: URL) -> [String]? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var out: [String] = []; var total = 0
        for i in 0..<min(doc.pageCount, 120) {
            let s = doc.page(at: i)?.string ?? ""; out.append(s); total += s.count
            if total > maxChars { break }
        }
        return out.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ? nil : out
    }

    /// Apple keeps iWork text in a format nothing else reads, but each document carries a preview
    /// image of its first page, which on-device text recognition can read. First page only, and
    /// only when the document was saved with a preview (the default). Said plainly in Help.
    static func iWork(_ url: URL) -> String? {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("askmac-iwork-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: tmp) }
        if isDir.boolValue {
            let preview = url.appendingPathComponent("preview.jpg")
            guard FileManager.default.fileExists(atPath: preview.path) else { return nil }
            return OCR.recognize(preview)
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-p", url.path, "preview.jpg"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard !data.isEmpty, (try? data.write(to: tmp)) != nil else { return nil }
        return OCR.recognize(tmp)
    }

    /// Office files are zips of XML; the text is what is left after the tags. Uses the system unzip.
    static func zipXML(_ url: URL, members: [String], also: String?) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", url.path] + members + (also.map { [$0] } ?? [])
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        // Paragraph and cell boundaries become newlines so passages split sensibly; every other tag goes.
        let text = xml.replacingOccurrences(of: "</(a:p|si|row|p:sp)>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</(a:t|t|c)>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func plain(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1)
    }

    /// Mail's .emlx: a byte count on the first line, the RFC 822 message, then a plist of flags.
    static func mail(from url: URL) -> Mail? {
        guard let d = try? Data(contentsOf: url), let s = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) else { return nil }
        var body = s
        if let nl = s.firstIndex(of: "\n"), Int(s[s.startIndex..<nl].trimmingCharacters(in: .whitespaces)) != nil { body = String(s[s.index(after: nl)...]) }
        if let r = body.range(of: "<?xml version", options: .backwards) { body = String(body[..<r.lowerBound]) }
        return parseRFC822(body)
    }

    static func parseRFC822(_ raw: String) -> Mail {
        let parts = raw.components(separatedBy: "\r\n\r\n").count > 1 ? raw.components(separatedBy: "\r\n\r\n") : raw.components(separatedBy: "\n\n")
        let headerText = parts.first ?? ""; var body = parts.dropFirst().joined(separator: "\n\n")
        var headers: [String: String] = [:]; var last = ""
        for line in headerText.components(separatedBy: .newlines) {
            if line.hasPrefix(" ") || line.hasPrefix("\t") { headers[last, default: ""] += " " + line.trimmingCharacters(in: .whitespaces) }
            else if let c = line.firstIndex(of: ":") { last = line[..<c].lowercased(); headers[last] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces) }
        }
        let ct = headers["content-type"] ?? ""
        if ct.contains("multipart"), let b = boundary(ct) {
            let sections = body.components(separatedBy: "--" + b).dropFirst().filter { !$0.hasPrefix("--") }
            var textPart: String?; var htmlPart: String?
            for sec in sections {
                let m = parseRFC822(sec.trimmingCharacters(in: .newlines))
                let sct = (m.subject.isEmpty ? "" : "") + (sectionHeader(sec, "content-type") ?? "")
                let enc = sectionHeader(sec, "content-transfer-encoding") ?? ""
                var content = m.body
                if enc.lowercased().contains("quoted-printable") { content = decodeQP(content) }
                if enc.lowercased().contains("base64"), let d = Data(base64Encoded: content.filter { !$0.isWhitespace }), let t = String(data: d, encoding: .utf8) { content = t }
                if sct.contains("text/plain"), textPart == nil { textPart = content }
                else if sct.contains("text/html"), htmlPart == nil { htmlPart = content }
                else if sct.contains("multipart"), textPart == nil { textPart = m.body }
            }
            body = textPart ?? htmlPart.map(stripHTML) ?? ""
        } else {
            let enc = headers["content-transfer-encoding"] ?? ""
            if enc.lowercased().contains("quoted-printable") { body = decodeQP(body) }
            if enc.lowercased().contains("base64"), let d = Data(base64Encoded: body.filter { !$0.isWhitespace }), let t = String(data: d, encoding: .utf8) { body = t }
            if ct.contains("text/html") { body = stripHTML(body) }
        }
        let date = headers["date"].flatMap { rfcDate($0) }
        return Mail(subject: decodeMIMEWords(headers["subject"] ?? ""), from: decodeMIMEWords(headers["from"] ?? ""), to: decodeMIMEWords(headers["to"] ?? ""), date: date, body: body.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    static func sectionHeader(_ sec: String, _ name: String) -> String? {
        for line in sec.components(separatedBy: .newlines).prefix(20) where line.lowercased().hasPrefix(name + ":") { return String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) }
        return nil
    }
    static func boundary(_ ct: String) -> String? {
        guard let r = ct.range(of: "boundary=", options: .caseInsensitive) else { return nil }
        var b = String(ct[r.upperBound...]); if let semi = b.firstIndex(of: ";") { b = String(b[..<semi]) }
        return b.trimmingCharacters(in: CharacterSet(charactersIn: "\" \r\n"))
    }
    static func decodeQP(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "")
        var bytes: [UInt8] = []; var i = out.startIndex
        while i < out.endIndex {
            if out[i] == "=", let e = out.index(i, offsetBy: 3, limitedBy: out.endIndex), let v = UInt8(out[out.index(after: i)..<e], radix: 16) { bytes.append(v); i = e }
            else { bytes += Array(String(out[i]).utf8); i = out.index(after: i) }
        }
        out = String(decoding: bytes, as: UTF8.self); return out
    }
    static func decodeMIMEWords(_ s: String) -> String {
        guard s.contains("=?") else { return s }
        var out = s
        let re = try! NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#)
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let whole = Range(m.range, in: s), let encR = Range(m.range(at: 2), in: s), let txtR = Range(m.range(at: 3), in: s) else { continue }
            let enc = s[encR].uppercased(); let txt = String(s[txtR])
            var decoded: String?
            if enc == "B", let d = Data(base64Encoded: txt) { decoded = String(data: d, encoding: .utf8) }
            else if enc == "Q" { decoded = decodeQP(txt.replacingOccurrences(of: "_", with: " ")) }
            if let decoded { out.replaceSubrange(whole, with: decoded) }
        }
        return out
    }
    static func rfcDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] { f.dateFormat = fmt; if let d = f.date(from: s.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)) { return d } }
        return nil
    }
    static func stripHTML(_ html: String) -> String {
        if let d = html.data(using: .utf8), let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) { return a.string }
        return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }
}
