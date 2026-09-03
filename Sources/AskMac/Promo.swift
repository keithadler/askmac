//  Ask for Mac — MIT licensed. See LICENSE.
//  Promo cards for the announcement, 1600×900 at 2×.

import AppKit
import SwiftUI

enum Promo {
    @MainActor static func render(to dir: URL, screenshots: URL) throws -> [URL] {
        let out = dir.appendingPathComponent("promo"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var written: [URL] = []
        let cards: [(String, String, String, String?)] = [
            ("1-hero", "Ask your Mac a question.\nGet the answer, and the file.", "Your documents, downloads, iCloud Drive and mail, read on this Mac. Every answer names its source and opens it.", "answer.png"),
            ("2-local", "Nothing leaves the Mac.", "Spotlight finds the files, the Mac reads them, Apple's on-device model writes the answer. No account, no upload, no index of your life on someone's server.", nil),
            ("3-honest", "When it doesn't know,\nit says so.", "Answers are built only from passages in your files, with numbered citations. Without Apple Intelligence it quotes the sentence instead of writing one.", "empty.png"),
            ("4-free", "Free. Open source. Also a command line.", "askmac \"lease deposit last week\"   MIT licensed, no server, no analytics.", nil),
        ]
        for (name, title, sub, shot) in cards {
            let view = Card(title: title, subtitle: sub, image: shot.flatMap { NSImage(contentsOf: screenshots.appendingPathComponent($0)) })
            let host = NSHostingView(rootView: view); host.frame = NSRect(x: 0, y: 0, width: 1600, height: 900)
            let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false); w.contentView = host; w.orderFront(nil)
            Screenshots.settle()
            written.append(try Screenshots.capture(w, to: out.appendingPathComponent("\(name).png"))); w.orderOut(nil)
        }
        return written
    }
    struct Card: View {
        let title: String, subtitle: String, image: NSImage?
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.22, blue: 0.40), Color(red: 0.05, green: 0.40, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 12) { Image(systemName: "questionmark.bubble.fill").font(.system(size: 34)); Text("Ask for Mac").font(.system(size: 30, weight: .semibold)) }.foregroundStyle(.white.opacity(0.85))
                        Text(title).font(.system(size: image == nil ? 64 : 50, weight: .bold, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                        Text(subtitle).font(.system(size: 26)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    }.frame(width: image == nil ? 1300 : 620, alignment: .leading)
                    if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 820).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(radius: 30, y: 12) }
                }.padding(80)
            }.frame(width: 1600, height: 900)
        }
    }
}
