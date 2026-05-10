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
    @State private var source: String = sampleSource
    @State private var svg: String = ""
    @State private var errorMessage: String?
    @State private var theme: String = "default"
    @State private var showEditor: Bool = true
    @State private var history: [String] = HistoryStore.load()
    @State private var pendingSave: Task<Void, Never>?

    private let themes = ["default", "dark", "forest", "neutral"]

    var body: some View {
        HSplitView {
            if showEditor {
                editorPane
                    .frame(minWidth: 320)
            }
            renderPane
                .frame(minWidth: 320)
        }
        .onAppear { render() }
        .onChange(of: source) { _ in render() }
        .onChange(of: theme) { _ in render() }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Paste") { pasteFromClipboard() }
                Picker("Theme", selection: $theme) {
                    ForEach(themes, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 180)
                Menu("History") {
                    if history.isEmpty {
                        Text("No history yet").disabled(true)
                    } else {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                            Button(historyLabel(item)) { source = item }
                        }
                        Divider()
                        Button("Clear history", role: .destructive) {
                            history.removeAll()
                            HistoryStore.save(history)
                        }
                    }
                }
                .frame(maxWidth: 130)
                Spacer()
                Button("Render") { render() }
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            MermaidEditor(text: $source)
                .border(Color.gray.opacity(0.3))
            if let err = errorMessage {
                Text(err)
                    .font(.callout)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }

    private var renderPane: some View {
        SVGView(svg: svg)
            .overlay(alignment: .topLeading) {
                Button {
                    showEditor.toggle()
                } label: {
                    Image(systemName: showEditor ? "sidebar.left" : "sidebar.leading")
                        .imageScale(.large)
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(8)
                .help(showEditor ? "Hide editor" : "Show editor")
            }
    }

    private func pasteFromClipboard() {
        if let s = NSPasteboard.general.string(forType: .string) {
            source = s
        }
    }

    private func render() {
        do {
            svg = try MermaidRenderer.renderSVG(source: source, theme: theme, background: "white")
            errorMessage = nil
            scheduleHistorySave(of: source)
        } catch {
            errorMessage = error.localizedDescription
        }
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
        if history.first == entry { return }
        history.removeAll { $0 == entry }
        history.insert(entry, at: 0)
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
        HistoryStore.save(history)
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

/// Display an SVG string inside a WKWebView.
struct SVGView: NSViewRepresentable {
    let svg: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
        <!doctype html>
        <html><head><meta charset='utf-8'>
        <style>
          html,body { margin:0; padding:0; height:100%; background:#fff; }
          body { display:flex; align-items:center; justify-content:center; }
          svg { max-width:100%; max-height:100%; }
        </style>
        </head><body>\(svg)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
