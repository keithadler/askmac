//  Ask for Mac — MIT licensed. See LICENSE.
//
//  Apple Notes, through the Notes app itself. Notes keeps its text in a private database, so the
//  honest way in is to ask the app (AppleScript), which macOS gates behind an Automation permission
//  the first time: "Ask for Mac wants to control Notes". Only used when a question mentions notes.

import Foundation
import AppKit

struct NoteHit { let id: String; let name: String; let body: String; let modified: Date? }

enum Notes {
    static var runner: (String) -> String? = { script in
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: d, as: UTF8.self) : nil
    }
    static let rs = "\u{1E}", us = "\u{1F}"   // record and unit separators, which no note contains

    static func script(_ terms: [String]) -> String {
        let clause = terms.prefix(2).map { "plaintext contains \"\($0.replacingOccurrences(of: "\"", with: ""))\"" }.joined(separator: " and ")
        return """
        tell application "Notes"
            set out to ""
            set hits to (every note whose \(clause))
            set n to 0
            repeat with x in hits
                set n to n + 1
                if n > 25 then exit repeat
                set out to out & (id of x) & "\(us)" & (name of x) & "\(us)" & ((modification date of x) as «class isot» as string) & "\(us)" & (plaintext of x) & "\(rs)"
            end repeat
            return out
        end tell
        """
    }

    static func parse(_ out: String) -> [NoteHit] {
        out.components(separatedBy: rs).compactMap { rec in
            let f = rec.components(separatedBy: us); guard f.count >= 4 else { return nil }
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
            return NoteHit(id: f[0], name: f[1], body: f[3].trimmingCharacters(in: .whitespacesAndNewlines), modified: f2.date(from: f[2]))
        }
    }

    static func search(_ terms: [String]) -> [NoteHit] {
        guard !terms.isEmpty, let out = runner(script(terms)) else { return [] }
        return parse(out)
    }

    static func show(id: String) {
        _ = runner("tell application \"Notes\"\nshow note id \"\(id)\"\nactivate\nend tell")
    }
}
