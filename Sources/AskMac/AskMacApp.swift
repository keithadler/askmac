//  Ask for Mac — MIT licensed. See LICENSE.
//
//  One window: a question, an answer, and the files it came from. Nothing leaves the Mac.

import SwiftUI
import AppKit
import ServiceManagement
import Quartz
import QuickLook

@main
struct AskMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AskModel.shared
    init() { CLI.runIfRequested() }
    var body: some Scene {
        WindowGroup("Ask for Mac") {
            MainView().environmentObject(model).frame(minWidth: 720, idealWidth: 860, minHeight: 480, idealHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Copy Answer with Sources") { AskModel.shared.copyAnswer() }.keyboardShortcut("c", modifiers: [.command, .shift])
                ForEach(1..<10, id: \.self) { n in Button("Open Source \(n)") { AskModel.shared.openSource(n) }.keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command) }
            }
            CommandGroup(replacing: .help) {
                Button("Ask for Mac Help") { Help.open() }
                Button("Check for Updates…") { Updates.checkAndPresent() }
                Button("Report a Problem…") { NSWorkspace.shared.open(URL(string: "https://github.com/keithadler/askmac/issues")!) }
                Divider()
                Button("More from the Same Maker…") { NSWorkspace.shared.open(URL(string: "https://keithadler.github.io")!) }
            }
        }
        Settings { SettingsView().environmentObject(model) }
        MenuBarExtra(isInserted: .constant(Prefs.menuBar)) {
            Button("Ask…") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.title == "Ask for Mac" }?.makeKeyAndOrderFront(nil) }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        } label: { Image(systemName: "questionmark.bubble") }
    }
}

@MainActor
final class AskModel: ObservableObject {
    static let shared = AskModel()
    @Published var question = ""
    @Published var answer: Answer?
    @Published var busy = false
    @Published var status = ""
    @Published var partial = ""
    @Published var history = Prefs.history
    @Published var modelNote = Answerer.modelStatus().why
    @Published var modelAvailable = Answerer.modelStatus().available
    private var task: Task<Void, Never>?
    func stop() { task?.cancel(); task = nil; busy = false; status = ""; partial = ""; if answer == nil { answer = Answer(text: "", how: .none, sources: [], elapsed: 0, candidates: 0, note: "Stopped.") } }
    func openSource(_ n: Int) {
        guard let a = answer, n >= 1, n <= a.sources.count else { return }
        let s = a.sources[n - 1]
        if let id = s.passage.source.noteId { Notes.show(id: id) } else { NSWorkspace.shared.open(s.passage.source.url) }
    }
    func copyAnswer() {
        guard let a = answer, a.how != .none else { return }
        var text = a.text + "\n"
        var seen = Set<URL>()
        for (i, s) in a.sources.enumerated() where seen.insert(s.passage.source.url).inserted || a.how == .model {
            text += "\n[\(i + 1)] \(s.passage.title)\(s.passage.page.map { ", page \($0)" } ?? "") — \(s.passage.source.noteId != nil ? "Apple Notes" : s.passage.source.url.path)"
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    func ask() {
        let q = question.trimmingCharacters(in: .whitespaces); guard q.count > 2, !busy else { return }
        busy = true; answer = nil; partial = ""; status = "Finding files…"
        if Prefs.keepHistory { var h = Prefs.history.filter { $0 != q }; h.append(q); Prefs.history = h; history = Prefs.history }
        task = Task {
            let a = await Ask.run(q, progress: { s in Task { @MainActor in self.status = s } }, onPartial: { p in Task { @MainActor in self.partial = p } })
            if Task.isCancelled { return }
            self.answer = a; self.busy = false; self.status = ""
        }
    }
}

struct MainView: View {
    @EnvironmentObject var model: AskModel
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.bubble").font(.title2).foregroundStyle(.secondary)
                TextField(model.answer == nil ? "Ask about your files, in your own words" : "Ask a follow-up, or something new", text: $model.question).textFieldStyle(.plain).font(.title2).focused($focused).onSubmit { model.ask() }
                    .onExitCommand { model.question = "" }
                if model.busy { ProgressView().controlSize(.small); Button("Stop") { model.stop() }.keyboardShortcut(".", modifiers: .command) }
                else { Button("Ask") { model.ask() }.keyboardShortcut(.defaultAction).disabled(model.question.count < 3) }
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let a = model.answer { AnswerView(answer: a) }
                    else if model.busy {
                        if !model.partial.isEmpty { Text(model.partial).font(.title3).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)) }
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.status).foregroundStyle(.secondary) }
                    }
                    else { EmptyStateView() }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Image(systemName: model.modelAvailable ? "cpu" : "quote.opening").foregroundStyle(.secondary)
                Text(model.modelNote).font(.caption).foregroundStyle(.secondary)
                if Prefs.includeMail, !FileManager.default.isReadableFile(atPath: Sources.mailFolder.path) {
                    Button("Mail not included") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }.buttonStyle(.link).font(.caption).help("Reading Mail needs Full Disk Access. Click to open the pane.")
                }
                Spacer()
                Text("Nothing leaves this Mac.").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.vertical, 8)
        }
        .onAppear { focused = true }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var model: AskModel
    let examples = ["lease deposit amount", "what did the dentist invoice say", "email from Sam about the roof last week", "tax return 2025 total", "meeting notes from Tuesday"]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask like you would ask a person who had read everything in your Documents, Desktop, Downloads, iCloud Drive and Mail.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Try").font(.headline)
            ForEach(examples, id: \.self) { e in Button { model.question = e; model.ask() } label: { Label(e, systemImage: "arrow.turn.down.right") }.buttonStyle(.link) }
            if !model.history.isEmpty {
                Text("Recent").font(.headline).padding(.top, 8)
                ForEach(model.history.reversed().prefix(8), id: \.self) { e in Button { model.question = e; model.ask() } label: { Label(e, systemImage: "clock") }.buttonStyle(.link) }
            }
        }
    }
}

struct AnswerView: View {
    let answer: Answer
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if answer.how == .none {
                Text(answer.note ?? "Nothing found.").font(.title3)
                Text("Try fewer words, or different ones. Ask for Mac searches Documents, Desktop, Downloads, iCloud Drive and Mail; other folders can be added in Settings.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(answer.how == .quote ? "“\(answer.text)”" : answer.text).font(.title3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if answer.how == .quote, let s = answer.sources.first { Text("Quoted from \(s.passage.title)").font(.caption).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                Text(answer.declined ? "Closest matches" : "Sources").font(.headline)
                if answer.declined { Text("These files matched the words but did not contain the answer. Try other words, or open one to look yourself.").font(.callout).foregroundStyle(.secondary) }
                VStack(spacing: 0) {
                    ForEach(Array(answer.sources.enumerated()), id: \.element) { i, s in
                        SourceRow(number: i + 1, scored: s)
                        if i < answer.sources.count - 1 { Divider().padding(.leading, 54) }
                    }
                }.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                Text(String(format: "%d %@ considered in %.1f seconds.", answer.candidates, answer.candidates == 1 ? "file" : "files", answer.elapsed)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SourceRow: View {
    let number: Int
    let scored: Scored
    @State private var expanded = false
    @State private var quickLook: URL?
    var body: some View {
        let url = scored.passage.source.url
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)").font(.caption.bold()).frame(width: 18, height: 18).background(.secondary.opacity(0.2), in: Circle())
                Image(nsImage: scored.passage.source.noteId != nil ? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes").map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(forFile: url.path)) : NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(scored.passage.title).font(.body.weight(.medium))
                        if let page = scored.passage.page { Text("page \(page)").font(.caption).padding(.horizontal, 5).padding(.vertical, 1).background(.secondary.opacity(0.15), in: Capsule()) }
                    }
                    Text([scored.passage.source.modified.map { $0.formatted(date: .abbreviated, time: .omitted) }, Sources.displayPath(url.deletingLastPathComponent())].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if let id = scored.passage.source.noteId { Button("Open in Notes") { Notes.show(id: id) } }
                else {
                    Button("Open") { NSWorkspace.shared.open(url) }
                    Button { quickLook = url } label: { Image(systemName: "eye") }.help("Quick Look")
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }.help("Show in Finder")
                }
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }.help("Show the passage")
            }
            if expanded { Text(scored.passage.text).font(.callout).textSelection(.enabled).padding(.leading, 56).foregroundStyle(.secondary) }
            else { Text(Passages.bestSentence(Query.parse(AskModel.shared.question).terms, in: scored.passage.text)).font(.callout).lineLimit(2).padding(.leading, 56).foregroundStyle(.secondary) }
        }.padding(.horizontal, 12).padding(.vertical, 8)
        .quickLookPreview($quickLook)
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AskModel
    @State private var folders = Sources.folders
    @State private var skipped = Prefs.skipped
    @State private var useModel = Prefs.useModel
    @State private var includeMail = Prefs.includeMail
    @State private var includeNotes = Prefs.includeNotes
    @State private var hotkey = Prefs.hotkey
    @State private var menuBar = Prefs.menuBar
    @State private var keepHistory = Prefs.keepHistory
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var updates = Updates.enabled
    var body: some View {
        Form {
            Section("Folders searched") {
                ForEach(folders, id: \.self) { f in HStack { Text(f.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")); Spacer(); Button("Remove") { folders.removeAll { $0 == f }; Prefs.folders = folders.map(\.path) } } }
                Button("Add Folder…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK, let u = p.url { folders.append(u); Prefs.folders = folders.map(\.path) }
                }
                Text("Skipped inside those").font(.caption).foregroundStyle(.secondary)
                ForEach(skipped, id: \.self) { f in HStack { Text(f.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).foregroundStyle(.secondary); Spacer(); Button("Unskip") { skipped.removeAll { $0 == f }; Prefs.skipped = skipped } } }
                Button("Skip a Folder…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.message = "Files in this folder will never be searched."
                    if p.runModal() == .OK, let u = p.url { skipped.append(u.path); Prefs.skipped = skipped }
                }
                Toggle("Include Mail", isOn: $includeMail).onChange(of: includeMail) { _, v in Prefs.includeMail = v }
                Toggle("Include Apple Notes when a question mentions notes", isOn: $includeNotes).onChange(of: includeNotes) { _, v in Prefs.includeNotes = v }
                Text("Notes are read through the Notes app; macOS asks once whether Ask for Mac may control it. Screenshots and photos are read with on-device text recognition when a question asks for them.").font(.caption).foregroundStyle(.secondary)
                if includeMail, !FileManager.default.isReadableFile(atPath: Sources.mailFolder.path) {
                    Text("Reading Mail needs Full Disk Access for Ask for Mac. Files work without it.").font(.caption).foregroundStyle(.secondary)
                    Button("Open Full Disk Access Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
                }
            }
            Section("Answers") {
                Toggle("Write answers with Apple Intelligence when available", isOn: $useModel).onChange(of: useModel) { _, v in Prefs.useModel = v }
                Text(model.modelNote).font(.caption).foregroundStyle(.secondary)
                Toggle("Remember recent questions", isOn: $keepHistory).onChange(of: keepHistory) { _, v in Prefs.keepHistory = v; if !v { Prefs.history = []; model.history = [] } }
            }
            Section {
                Toggle("Open at login", isOn: $login).onChange(of: login) { _, v in if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() } }
                Toggle("Show in the menu bar", isOn: $menuBar).onChange(of: menuBar) { _, v in Prefs.menuBar = v }
                Toggle("⌥ Space brings the window forward", isOn: $hotkey).onChange(of: hotkey) { _, v in Prefs.hotkey = v; Hotkey.register() }
                Toggle("Check for updates daily", isOn: $updates).onChange(of: updates) { _, v in Updates.enabled = v }
            }
        }.formStyle(.grouped).frame(width: 520, height: 520)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["ASKMAC_HOME"] == nil, !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered"); try? SMAppService.mainApp.register()
        }
        Updates.scheduleBackgroundChecks()
        Hotkey.onPress = {
            if let w = NSApp.windows.first(where: { $0.title == "Ask for Mac" }), w.isKeyWindow, NSApp.isActive { w.orderOut(nil); NSApp.hide(nil) }
            else { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.title == "Ask for Mac" }?.makeKeyAndOrderFront(nil) }
        }
        if ProcessInfo.processInfo.environment["ASKMAC_HOME"] == nil { Hotkey.register() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !Prefs.menuBar }
}

enum Help {
    static var pageName: String { (Locale.preferredLanguages.first ?? "en").hasPrefix("es") ? "Help.es" : "Help" }
    static var bundledPage: URL? {
        if let url = Bundle.main.url(forResource: pageName, withExtension: "html") { return url }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" { if url.pathExtension == "app", let u = Bundle(url: url)?.url(forResource: pageName, withExtension: "html") { return u }; url = url.deletingLastPathComponent() }
        return nil
    }
    @MainActor static func open() { NSWorkspace.shared.open(bundledPage ?? URL(string: "https://github.com/keithadler/askmac#readme")!) }
}
