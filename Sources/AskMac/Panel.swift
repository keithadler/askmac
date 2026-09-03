//  Ask for Mac — MIT licensed. See LICENSE.
//
//  The quick panel: ⌥ Space from any app, a floating field like Spotlight's, the answer under it,
//  Escape to dismiss. It does not steal the other app's focus for longer than the question takes.

import AppKit
import SwiftUI
import Combine

@MainActor
final class PanelController {
    static let shared = PanelController()
    private var panel: NSPanel?
    private var monitor: Any?
    private var host: NSHostingView<AnyView>?
    private var sink: AnyCancellable?
    private var resignObserver: Any?

    func toggle() { if let p = panel, p.isVisible { hide() } else { show() } }

    func show() {
        if panel == nil { build() }
        guard let panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let h = fittedHeight()
        panel.setFrame(NSRect(x: f.midX - 360, y: f.maxY - h - f.height * 0.12, width: 720, height: h), display: false)
        panel.makeKeyAndOrderFront(nil)
        AskModel.shared.focusRequest += 1
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.hide(); return nil }   // Escape
            return e
        }
        // Like Spotlight: clicking anywhere else puts it away.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in self?.hide() }
    }

    func hide() {
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
    }

    /// The panel is as tall as its content, within reason; the top edge stays put as it grows.
    private func fittedHeight() -> CGFloat { min(max(host?.fittingSize.height ?? 72, 72), 640) }
    private func resize() {
        guard let panel, panel.isVisible else { return }
        let h = fittedHeight()
        guard abs(panel.frame.height - h) > 1 else { return }
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - h, width: 720, height: h), display: true, animate: true)
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        p.titleVisibility = .hidden; p.titlebarAppearsTransparent = true
        p.standardWindowButton(.closeButton)?.isHidden = true; p.standardWindowButton(.miniaturizeButton)?.isHidden = true; p.standardWindowButton(.zoomButton)?.isHidden = true
        p.level = .floating; p.isFloatingPanel = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isMovableByWindowBackground = true; p.becomesKeyOnlyIfNeeded = false
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        let hv = NSHostingView(rootView: AnyView(PanelView().environmentObject(AskModel.shared).frame(width: 720)))
        hv.sizingOptions = [.intrinsicContentSize]   // measure, but never resize the window on its own
        p.contentView = hv; host = hv
        p.isReleasedWhenClosed = false
        panel = p
        sink = AskModel.shared.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in DispatchQueue.main.async { self?.resize() } }
    }
}

struct PanelView: View {
    @EnvironmentObject var model: AskModel
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.bubble").font(.system(size: 22)).foregroundStyle(.secondary)
                if let scope = model.scope { ScopeChip(scope: scope) }
                TextField(model.answer == nil ? "Ask about your files" : "Ask a follow-up", text: $model.question)
                    .textFieldStyle(.plain).font(.system(size: 24, weight: .regular)).focused($focused)
                    .onSubmit { model.ask() }
                if model.busy { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 20).padding(.vertical, 16)
            if model.answer != nil || model.busy || !model.pendingSources.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let a = model.answer { AnswerView(answer: a) }
                        else if model.busy { ProgressBody() }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 560)
            } else if !model.suggestions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recently changed").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.suggestions, id: \.self) { s in
                        Button { model.question = s; model.ask() } label: { Label(s, systemImage: "arrow.turn.down.right").lineLimit(1) }.buttonStyle(.plain).foregroundStyle(.primary)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .onAppear { focused = true }
        .onChange(of: model.focusRequest) { _, _ in focused = true }
    }
}

struct ScopeChip: View {
    @EnvironmentObject var model: AskModel
    let scope: URL
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder"); Text(scope.lastPathComponent)
            Button { model.scope = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Search everywhere again")
        }.font(.callout).padding(.horizontal, 8).padding(.vertical, 4).background(.tint.opacity(0.15), in: Capsule()).help("This question looks only in \(scope.path)")
    }
}

/// While working: the status line, and the sources as soon as they are known, so the wait shows progress.
struct ProgressBody: View {
    @EnvironmentObject var model: AskModel
    var body: some View {
        if !model.partial.isEmpty {
            Text(model.partial).font(.title3).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        } else {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.status).foregroundStyle(.secondary) }
        }
        if !model.pendingSources.isEmpty {
            Text("Sources").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(model.pendingSources.enumerated()), id: \.element) { i, s in
                    SourceRow(number: i + 1, scored: s)
                    if i < model.pendingSources.count - 1 { Divider().padding(.leading, 54) }
                }
            }.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// Questions from the person's own recently changed documents, so the empty state is never generic.
enum Suggest {
    static func recent(limit: Int = 4) -> [String] {
        var args: [String] = []
        for f in Sources.folders { args += ["-onlyin", f.path] }
        let since = Sources.iso(Date().addingTimeInterval(-21 * 86400))
        let q = "kMDItemContentModificationDate >= $time.iso(\(since)) && (kMDItemContentType == \"com.adobe.pdf\" || kMDItemContentType == \"org.openxmlformats.wordprocessingml.document\" || kMDItemContentType == \"com.apple.iwork.pages.sffpages\" || kMDItemContentType == \"net.daringfireball.markdown\" || kMDItemContentType == \"public.plain-text\")"
        let paths = Sources.mdfind(args + [q]).filter { !Sources.skipped(URL(fileURLWithPath: $0)) && !$0.contains("/Library/") }
        let urls = paths.prefix(200).map { URL(fileURLWithPath: $0) }
        let dated = urls.compactMap { u -> (URL, Date)? in (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (u, $0) } }
            .sorted { $0.1 > $1.1 }
        var out: [String] = []; var seen = Set<String>()
        for (u, _) in dated {
            let name = u.deletingPathExtension().lastPathComponent
            guard name.count > 3, name.count < 60, !name.lowercased().hasPrefix("untitled"), seen.insert(name.lowercased()).inserted else { continue }
            out.append("What does “\(name)” say?")
            if out.count >= limit { break }
        }
        return out
    }
}
