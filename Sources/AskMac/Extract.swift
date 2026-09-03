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

    struct Mail { var subject: String; var from: String; var to: String; var date: Date?; var body: String }

    static func text(from url: URL) -> String? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize), size <= maxBytes else { return nil }
        let ext = url.pathExtension.lowercased()
        var out: String?
        switch ext {
        case "pdf": out = PDFDocument(url: url)?.string
        case "emlx", "eml": out = mail(from: url).map { "\($0.subject)\nFrom: \($0.from)\nTo: \($0.to)\n\n\($0.body)" }
        case "rtf", "rtfd", "doc", "docx", "html", "htm", "odt", "webarchive":
            out = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        case "csv", "tsv", "txt", "md", "markdown", "text", "json", "xml", "yaml", "yml", "log", "swift", "py", "js", "ts", "sh", "rb", "go", "c", "h", "m", "java", "tex", "org", "ics", "vcf", "eml2":
            out = plain(url)
        case "png", "jpg", "jpeg", "heic", "tiff", "gif", "webp", "bmp": out = OCR.recognize(url)
        case "xlsx", "pptx", "numbers", "pages", "key": out = nil      // not this version
        default:
            // Unknown extension: try it as text when it looks like text.
            if let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.prefix(4096).allSatisfy({ $0 == 9 || $0 == 10 || $0 == 13 || $0 >= 32 }) { out = String(decoding: d, as: UTF8.self) }
        }
        guard var s = out?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.count > maxChars { s = String(s.prefix(maxChars)) }
        return s
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
