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
    @State private var showHistory: Bool = false
    @StateObject private var web = WebViewHolder()

    private let themes = ["default", "dark", "forest", "neutral"]

    var body: some View {
        NavigationSplitView {
            editorPane
                .navigationSplitViewColumnWidth(min: 280, ideal: 400)
        } detail: {
            SVGView(svg: svg, webView: web.webView)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        Button {
                            copyPNGToClipboard()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("Copy image")

                        Button {
                            savePNGToFile()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .help("Save image…")
                    }
                    .disabled(svg.isEmpty)
                    .padding(8)
                }
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

                Button {
                    showHistory.toggle()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("History")
                .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                    historyPopover
                }

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
            blurEditor()
            source = s
            render()
        }
    }

    private func selectHistoryItem(_ item: String) {
        blurEditor()
        source = item
        render()
        showHistory = false
    }

    private func removeHistoryItem(at index: Int) {
        guard history.indices.contains(index) else { return }
        history.remove(at: index)
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
                do {
                    try data.write(to: url)
                } catch {
                    errorMessage = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func snapshotPNG(completion: @escaping (Data?) -> Void) {
        guard !svg.isEmpty else { completion(nil); return }
        let config = WKSnapshotConfiguration()
        web.webView.takeSnapshot(with: config) { image, error in
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else {
                if let error { errorMessage = "Snapshot failed: \(error.localizedDescription)" }
                completion(nil)
                return
            }
            completion(png)
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

/// Holds a WKWebView so ContentView can both display it (via SVGView) and
/// snapshot it for PNG export.
final class WebViewHolder: ObservableObject {
    let webView: WKWebView
    init() {
        let w = WKWebView()
        w.setValue(false, forKey: "drawsBackground")
        self.webView = w
    }
}

/// Display an SVG string inside a WKWebView.
struct SVGView: NSViewRepresentable {
    let svg: String
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }

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
