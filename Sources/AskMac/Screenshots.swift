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
        Prefs.folders = [tmp.path]; Ask.useSpotlight = false
        defer { Prefs.defaults = .standard; Ask.useSpotlight = true }
        try Demo.write(tmp)
        let model = AskModel.shared
        model.history = ["tax return 2025 total", "email from Sam about the roof last week", "dentist invoice crown"]
        model.modelNote = "Apple Intelligence is on; answers are written on this Mac."; model.modelAvailable = true

        var written: [URL] = []
        for (suffix, appearance) in [("", NSAppearance.Name.darkAqua), ("-light", .aqua)] {
            app.appearance = NSAppearance(named: appearance)
            for (name, question, demoAnswer) in [("answer", "how much was the lease deposit", "The security deposit on the Woodland Ave lease is $2,400, due at signing, with rent of $1,950 a month [1]. The landlord confirmed receipt on August 14 [2]."),
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
            }
        }
        if announce { written += try Promo.render(to: dir, screenshots: dir) }
        return written
    }
    @MainActor static func settle() { let until = Date().addingTimeInterval(0.8); while Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) } }
    @MainActor static func capture(_ window: NSWindow, to url: URL) throws -> URL {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { throw NSError(domain: "shots", code: 1) }
        let fn = unsafeBitCast(sym, to: Fn.self)
        guard let img = fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 4)?.takeRetainedValue() else { throw NSError(domain: "shots", code: 2) }
        guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { throw NSError(domain: "shots", code: 3) }
        try png.write(to: url); return url
    }
}

enum Demo {
    static func write(_ dir: URL) throws {
        let docs = dir.appendingPathComponent("Documents"); try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        func put(_ name: String, _ text: String, daysAgo: Int) throws {
            let u = docs.appendingPathComponent(name); try text.write(to: u, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(daysAgo) * 86400)], ofItemAtPath: u.path)
        }
        try put("Lease Woodland Ave.txt", "Residential lease, 12 Woodland Ave.\n\nSecurity deposit: $2,400, due at signing. Rent: $1,950 per month, due on the first.\n\nTenant: Sam Rivera. Landlord: Pine Street Holdings.\n\nTerm: twelve months beginning September 1.", daysAgo: 22)
        try put("Deposit receipt.txt", "Pine Street Holdings\n\nReceived from Sam Rivera on August 14: $2,400 security deposit for 12 Woodland Ave. Thank you.", daysAgo: 20)
        try put("Dentist invoice.md", "# Dr. Lee, DDS\n\nCrown, lower molar: 1,150.00\nCleaning: 180.00\n\nPaid in full, thank you.", daysAgo: 60)
        try put("Tax return 2025 summary.txt", "2025 return summary. Total tax: 14,212. Refund: 1,380. Filed April 9.", daysAgo: 140)
        try put("Recipes.txt", "Lemon cake: 3 eggs, 200 g sugar, zest of two lemons, 180 g flour.", daysAgo: 300)
    }
}
