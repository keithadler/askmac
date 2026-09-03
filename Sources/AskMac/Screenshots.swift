//  Ask for Mac — MIT licensed. See LICENSE.
//
//  `askmac screenshots <dir>`: the window answering a question over a demo folder (Sam Rivera's
//  files), for the README. Nothing here reads the real folders.

import AppKit
import SwiftUI

enum Screenshots {
    @MainActor
    static func render(to dir: URL, announce: Bool) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular); app.activate(ignoringOtherApps: true)
        if app.applicationIconImage.size.width == 0 || Bundle.main.bundleIdentifier == nil, let icon = NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/AppIcon.icns") { app.applicationIconImage = icon }
        let tmp = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: tmp) }
        Prefs.defaults = UserDefaults(suiteName: "com.keithadler.askmac.screenshots")!
        Prefs.defaults.removePersistentDomain(forName: "com.keithadler.askmac.screenshots")
        Prefs.folders = [tmp.appendingPathComponent("Documents").path]; Ask.useSpotlight = false
        defer { Prefs.defaults = .standard; Ask.useSpotlight = true }
        try Demo.write(tmp)
        let model = AskModel.shared
        model.history = ["tax return 2025 total", "email from Sam about the roof last week", "dentist invoice crown"]
        model.suggestions = ["What does “Lease Woodland Ave” say?", "What does “Deposit receipt” say?", "What does “Dentist invoice” say?", "What does “Tax return 2025 summary” say?"]
        model.modelNote = "Apple Intelligence is on; answers are written on this Mac."; model.modelAvailable = true

        var written: [URL] = []
        for (suffix, appearance) in [("", NSAppearance.Name.darkAqua), ("-light", .aqua)] {
            app.appearance = NSAppearance(named: appearance)
            for (name, question, demoAnswer) in [("answer", "how much was the lease deposit", "The security deposit on the Woodland Ave lease is $2,400, due at signing, with rent of $1,950 a month [2]. The landlord confirmed receipt of it on August 14 [1]."),
                                                 ("empty", "", nil as String?)] {
                model.question = question; model.answer = nil
                if !question.isEmpty {
                    let sem = DispatchSemaphore(value: 0); var a: Answer?
                    Task.detached { a = await Ask.run(question, useModel: false); sem.signal() }; sem.wait()
                    if var a, let demoAnswer { a.text = demoAnswer; a.how = .model; a.elapsed = 1.2; model.answer = a } else { model.answer = a }
                }
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                w.title = "Ask for Mac"; w.contentView = NSHostingView(rootView: MainView().environmentObject(model).frame(width: 860, height: 600)); w.center(); w.makeKeyAndOrderFront(nil)
                settle(); written.append(try capture(w, to: dir.appendingPathComponent("\(name)\(suffix).png"))); w.orderOut(nil)
                // The quick panel, floating over a neutral backdrop so its material shows.
                let panelHost = NSHostingView(rootView: PanelView().environmentObject(model).frame(width: 720)); panelHost.sizingOptions = [.intrinsicContentSize]
                let ph = min(max(panelHost.fittingSize.height, 72), 640)
                let back = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: ph + 140), styleMask: [.borderless], backing: .buffered, defer: false)
                back.backgroundColor = appearance == .darkAqua ? NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.30, alpha: 1) : NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.92, alpha: 1); back.center(); back.orderFront(nil)
                let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: ph), styleMask: [.borderless], backing: .buffered, defer: false)
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
                panel.contentView = panelHost
                panel.setFrameOrigin(NSPoint(x: back.frame.midX - 360, y: back.frame.midY - ph / 2)); panel.level = .floating; panel.makeKeyAndOrderFront(nil)
                settle()
                written.append(try capture(back, to: dir.appendingPathComponent("panel-\(name)\(suffix).png"), also: panel))
                panel.orderOut(nil); back.orderOut(nil)
            }
        }
        if announce { written += try Promo.render(to: dir, screenshots: dir) }
        return written
    }
    @MainActor static func settle() { let until = Date().addingTimeInterval(0.8); while Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) } }
    /// Nominal resolution (points) by default; `retina` asks for the 2× pixels, which the phone-sized cards need.
    @MainActor static func image(of window: NSWindow, retina: Bool = false) throws -> CGImage {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { throw NSError(domain: "shots", code: 1) }
        let fn = unsafeBitCast(sym, to: Fn.self)
        guard let i = fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | (retina ? 1 << 3 : 1 << 4))?.takeRetainedValue() else { throw NSError(domain: "shots", code: 2) }
        return i
    }

    /// One window, or a floating window composited over a backdrop window at its true offset.
    @MainActor static func capture(_ window: NSWindow, to url: URL, also: NSWindow? = nil, retina: Bool = false) throws -> URL {
        var img = try image(of: window, retina: retina)
        if let also {
            let top = try image(of: also)
            let scale = CGFloat(img.width) / window.frame.width
            let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            let x = (also.frame.minX - window.frame.minX) * scale, y = (also.frame.minY - window.frame.minY) * scale
            ctx.draw(top, in: CGRect(x: x, y: y, width: CGFloat(top.width), height: CGFloat(top.height)))
            img = ctx.makeImage()!
        }
        guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { throw NSError(domain: "shots", code: 3) }
        try png.write(to: url); return url
    }
}

extension NSRect {
    /// Window frames are bottom-left; CGWindowList wants top-left, main-screen relative.
    func toCG() -> CGRect { let h = NSScreen.screens.first?.frame.height ?? 0; return CGRect(x: minX, y: h - maxY, width: width, height: height) }
}

enum Demo {
    static func write(_ dir: URL) throws {
        let docs = dir.appendingPathComponent("Documents"); try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        func put(_ name: String, _ text: String, daysAgo: Int) throws {
            let u = docs.appendingPathComponent(name); try text.write(to: u, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(daysAgo) * 86400)], ofItemAtPath: u.path)
        }
        try put("Lease Woodland Ave.txt", "Residential lease, 12 Woodland Ave.\n\nSecurity deposit: $2,400, due at signing. Rent: $1,950 per month, due on the first.\n\nTenant: Sam Rivera. Landlord: Pine Street Holdings.\n\nTerm: twelve months beginning September 1.", daysAgo: 22)
        try put("Deposit receipt.txt", "Pine Street Holdings\n\nReceived from Sam Rivera on August 14: $2,400 security deposit for the 12 Woodland Ave lease. Thank you.", daysAgo: 20)
        try put("Dentist invoice.md", "# Dr. Lee, DDS\n\nCrown, lower molar: 1,150.00\nCleaning: 180.00\n\nPaid in full, thank you.", daysAgo: 60)
        try put("Tax return 2025 summary.txt", "2025 return summary. Total tax: 14,212. Refund: 1,380. Filed April 9.", daysAgo: 140)
        try put("Recipes.txt", "Lemon cake: 3 eggs, 200 g sugar, zest of two lemons, 180 g flour.", daysAgo: 300)
    }
}
