//  Ask for Mac — MIT licensed. See LICENSE.
//  Promo cards for the announcement, 1600×900 at 2×.

import AppKit
import SwiftUI

enum Promo {
    @MainActor static func render(to dir: URL, screenshots: URL) throws -> [URL] {
        let out = dir.appendingPathComponent("promo"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var written: [URL] = []
        let cards: [(String, String, String, String?)] = [
            ("1-hero", "Ask your Mac a question.\nGet the answer, and the file.", "⌥ Space from any app. Your documents, downloads, iCloud Drive and mail, read on this Mac. Every answer names its source and opens it.", "panel-answer.png"),
            ("2-local", "Nothing leaves the Mac.", "Spotlight finds the files, the Mac reads them, Apple's on-device model writes the answer. No account, no upload, no index of your life on someone's server.", nil),
            ("3-honest", "When it doesn't know,\nit says so.", "Answers are built only from passages in your files, with numbered citations. Without Apple Intelligence it quotes the sentence instead of writing one.", "empty.png"),
            ("4-free", "Free. Open source. Also a command line.", "askmac \"lease deposit last week\"   MIT licensed, no server, no analytics.", nil),
        ]
        // 9:16 for TikTok, Reels and Stories. Laid out at 540×960 points so a Retina capture is exactly 1080×1920.
        let vertical = Vertical(image: NSImage(contentsOf: screenshots.appendingPathComponent("panel-answer.png")))
        let vh = NSHostingView(rootView: vertical); vh.frame = NSRect(x: 0, y: 0, width: 540, height: 960)
        let vw = NSWindow(contentRect: vh.frame, styleMask: [.borderless], backing: .buffered, defer: false); vw.contentView = vh; vw.orderFront(nil)
        Screenshots.settle()
        written.append(try Screenshots.capture(vw, to: out.appendingPathComponent("5-vertical.png"), retina: true)); vw.orderOut(nil)
        for (name, title, sub, shot) in cards {
            let view = Card(title: title, subtitle: sub, image: shot.flatMap { NSImage(contentsOf: screenshots.appendingPathComponent($0)) })
            let host = NSHostingView(rootView: view); host.frame = NSRect(x: 0, y: 0, width: 1600, height: 900)
            let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false); w.contentView = host; w.orderFront(nil)
            Screenshots.settle()
            written.append(try Screenshots.capture(w, to: out.appendingPathComponent("\(name).png"))); w.orderOut(nil)
        }
        return written
    }
    /// One screen for a phone: what it is, three lines of what it does, where to get it.
    struct Vertical: View {
        let image: NSImage?
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.06, green: 0.16, blue: 0.34), Color(red: 0.05, green: 0.42, blue: 0.46)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) { Image(systemName: "questionmark.bubble.fill").font(.system(size: 22)); Text("Ask for Mac").font(.system(size: 21, weight: .semibold)) }.foregroundStyle(.white.opacity(0.9))
                    Text("Free Mac app.").font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(.white).padding(.top, 18)
                    Text("Ask your Mac a question.\nGet the answer, and the file.").font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 470).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(radius: 22, y: 10).padding(.top, 22) }
                    VStack(alignment: .leading, spacing: 12) {
                        Line(icon: "lock.fill", text: "Nothing leaves your Mac. No account, no upload.")
                        Line(icon: "doc.text.magnifyingglass", text: "Every answer names the file it came from and opens it.")
                        Line(icon: "keyboard", text: "⌥ Space from any app. Mail, PDFs, notes, screenshots.")
                    }.padding(.top, 24)
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Free. Open source.").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                            Text("keithadler.github.io").font(.system(size: 22, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.92))
                        }
                        Spacer()
                        Text("MIT · macOS 14+").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                    }
                }.padding(35)
            }.frame(width: 540, height: 960)
        }
        struct Line: View {
            let icon: String, text: String
            var body: some View {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 26)
                    Text(text).font(.system(size: 17.5, weight: .medium)).foregroundStyle(.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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
