import SwiftUI
import AppKit
import WebKit

private let sampleSource = """
flowchart LR
    A[Start] --> B{Decide}
    B -->|yes| C[Render]
    B -->|no| D[Skip]
    C --> E[Done]
    D --> E
"""

private let historyKey = "mermaidHistory"
private let historyLimit = 15

struct ContentView: View {
    @State private var source: String = HistoryStore.load().first ?? sampleSource
    @State private var theme: String = "default"
    @State private var history: [String] = HistoryStore.load()
    @State private var pendingSave: Task<Void, Never>?
    @State private var showHistory: Bool = false
    /// The history entry the user is currently iterating on. Edits replace
    /// this entry in place instead of stacking up as new items.
    @State private var editingOriginal: String? = HistoryStore.load().first
    @StateObject private var web = MermaidWebView()

    private let themes = ["default", "dark", "forest", "neutral"]

    var body: some View {
        NavigationSplitView {
            editorPane
                .navigationSplitViewColumnWidth(min: 280, ideal: 400)
        } detail: {
            MermaidWebContainer(webView: web.webView)
                .toolbar {
                    ToolbarItemGroup {
                        Button(action: copyPNGToClipboard) {
                            Label("Copy PNG", systemImage: "doc.on.doc")
                        }
                        .help("Copy image")
                        .disabled(web.svg.isEmpty)

                        Button(action: savePNGToFile) {
                            Label("Save PNG…", systemImage: "square.and.arrow.down")
                        }
                        .help("Save image…")
                        .disabled(web.svg.isEmpty)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { render() }
        .onChange(of: source) { render() }
        .onChange(of: theme) { render() }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorActionBar
            MermaidEditor(text: $source)
                .border(Color.gray.opacity(0.3))
            if let err = web.errorMessage {
                Text(err)
                    .font(.callout)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .overlay(alignment: .trailing) {
            // Hover area at the divider edge. WKWebView in the detail pane
            // intercepts cursor updates from NavigationSplitView, so place the
            // resize-cursor zone on the editor side of the seam instead.
            Color.clear
                .frame(width: 6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }

    private var editorActionBar: some View {
        HStack(spacing: 10) {
            Button(action: pasteFromClipboard) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Paste from clipboard")

            Menu {
                Picker(selection: $theme) {
                    ForEach(themes, id: \.self) { Text($0).tag($0) }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Theme: \(theme)")

            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("History")
            .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                historyPopover
            }

            Spacer()
        }
    }

    private func pasteFromClipboard() {
        if let s = NSPasteboard.general.string(forType: .string) {
            blurEditor()
            source = s
            editingOriginal = nil
            render()
        }
    }

    private func selectHistoryItem(_ item: String) {
        blurEditor()
        source = item
        editingOriginal = item
        render()
        showHistory = false
    }

    private func removeHistoryItem(at index: Int) {
        guard history.indices.contains(index) else { return }
        let removed = history.remove(at: index)
        if editingOriginal == removed { editingOriginal = nil }
        HistoryStore.save(history)
    }

    /// Resign first responder so the editor lets external `source` updates
    /// flow through MermaidEditor.updateNSView (which otherwise skips
    /// syncs while the text view is focused).
    private func blurEditor() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    @ViewBuilder
    private var historyPopover: some View {
        VStack(spacing: 0) {
            if history.isEmpty {
                Text("No history yet")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(history.enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 6) {
                                Button {
                                    selectHistoryItem(item)
                                } label: {
                                    Text(historyLabel(item))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    removeHistoryItem(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            if idx < history.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)

                Divider()
                Button(role: .destructive) {
                    history.removeAll()
                    editingOriginal = nil
                    HistoryStore.save(history)
                    showHistory = false
                } label: {
                    Label("Clear history", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(8)
                .foregroundColor(.red)
            }
        }
        .frame(width: 260)
    }

    private func copyPNGToClipboard() {
        snapshotPNG { data in
            guard let data else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: .png)
        }
    }

    private func savePNGToFile() {
        snapshotPNG { data in
            guard let data else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "diagram.png"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }

    private func snapshotPNG(completion: @escaping (Data?) -> Void) {
        guard !web.svg.isEmpty else { completion(nil); return }
        let config = WKSnapshotConfiguration()
        web.webView.takeSnapshot(with: config) { image, _ in
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { completion(nil); return }
            completion(png)
        }
    }

    private func render() {
        web.render(source: source, theme: theme)
        scheduleHistorySave(of: source)
    }

    private func scheduleHistorySave(of snapshot: String) {
        pendingSave?.cancel()
        pendingSave = Task { [snapshot] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                guard snapshot == source else { return }
                addToHistory(snapshot)
            }
        }
    }

    private func addToHistory(_ entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // The baseline represents the prior state of *this* diagram, so the
        // edit should replace it rather than coexist with it.
        let baselineToRemove = editingOriginal.flatMap { $0 != entry ? $0 : nil }

        if history.first == entry && baselineToRemove == nil {
            editingOriginal = entry
            return
        }

        if let baseline = baselineToRemove {
            history.removeAll { $0 == baseline }
        }
        history.removeAll { $0 == entry }
        history.insert(entry, at: 0)
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
        HistoryStore.save(history)
        editingOriginal = entry
    }

    private func historyLabel(_ s: String) -> String {
        let firstLine = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        let limit = 50
        if trimmed.isEmpty { return "(empty)" }
        if trimmed.count > limit {
            return String(trimmed.prefix(limit)) + "…"
        }
        return trimmed
    }
}

private enum HistoryStore {
    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }
    static func save(_ items: [String]) {
        UserDefaults.standard.set(items, forKey: historyKey)
    }
}

/// Hosts a single WKWebView that loads `mermaid.html` once and renders
/// diagrams via `mermaid.js`. The latest SVG is mirrored to Swift through
/// a message handler so Copy/Save PNG can stay enabled.
@MainActor
final class MermaidWebView: NSObject, ObservableObject {
    @Published var svg: String = ""
    @Published var errorMessage: String? = nil
    let webView: WKWebView

    private let bridge: Bridge
    private var isReady = false
    private var pendingSource: String?
    private var pendingTheme: String?
    private var inflight = false

    override init() {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        config.userContentController = ucc
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv
        self.bridge = Bridge()
        super.init()

        bridge.owner = self
        ucc.add(bridge, name: "mermaid")
        wv.navigationDelegate = bridge

        if let url = Bundle.module.url(forResource: "mermaid", withExtension: "html") {
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func render(source: String, theme: String) {
        pendingSource = source
        pendingTheme = theme
        pump()
    }

    fileprivate func didFinishLoad() {
        isReady = true
        pump()
    }

    fileprivate func receive(message body: Any) {
        inflight = false
        if let dict = body as? [String: Any] {
            if let ok = dict["ok"] as? Bool, ok {
                self.svg = dict["svg"] as? String ?? ""
                self.errorMessage = nil
            } else {
                self.errorMessage = dict["error"] as? String ?? "render error"
            }
        }
        pump()
    }

    private func pump() {
        guard isReady, !inflight,
              let src = pendingSource,
              let theme = pendingTheme
        else { return }
        pendingSource = nil
        pendingTheme = nil
        inflight = true

        let js = "renderMermaid(\(jsString(src)), \(jsString(theme)))"
        webView.evaluateJavaScript(js)
    }

    private func jsString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s),
              let json = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return json
    }

    /// NSObject subclass so WebKit can hold a weak protocol reference without
    /// forcing `MermaidWebView` itself to inherit from NSObject in an awkward
    /// way (it already does, but this keeps the message-handler surface tight).
    private final class Bridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var owner: MermaidWebView?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in owner?.didFinishLoad() }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let body = message.body
            Task { @MainActor in owner?.receive(message: body) }
        }
    }
}

/// SwiftUI wrapper around the shared WKWebView owned by `MermaidWebView`.
struct MermaidWebContainer: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
