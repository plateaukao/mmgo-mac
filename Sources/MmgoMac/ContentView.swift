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
    @State private var svg: String = ""
    @State private var errorMessage: String?
    @State private var theme: String = "default"
    @State private var history: [String] = HistoryStore.load()
    @State private var pendingSave: Task<Void, Never>?

    private let themes = ["default", "dark", "forest", "neutral"]

    var body: some View {
        NavigationSplitView {
            editorPane
                .navigationSplitViewColumnWidth(min: 280, ideal: 400)
        } detail: {
            SVGView(svg: svg)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { render() }
        .onChange(of: source) { render() }
        .onChange(of: theme) { render() }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Paste from clipboard")

                Menu {
                    Picker(selection: $theme) {
                        ForEach(themes, id: \.self) { Text($0).tag($0) }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Theme: \(theme)")

                Menu {
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
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("History")

                Spacer()

                Button {
                    render()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Render (⌘↩)")
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
