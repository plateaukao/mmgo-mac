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

struct ContentView: View {
    @State private var source: String = sampleSource
    @State private var svg: String = ""
    @State private var errorMessage: String?
    @State private var theme: String = "default"

    private let themes = ["default", "dark", "forest", "neutral"]

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Paste") { pasteFromClipboard() }
                    Picker("Theme", selection: $theme) {
                        ForEach(themes, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 200)
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
            .frame(minWidth: 320)

            SVGView(svg: svg)
                .frame(minWidth: 320)
        }
        .onAppear { render() }
        .onChange(of: source) { _ in render() }
        .onChange(of: theme) { _ in render() }
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
        } catch {
            errorMessage = error.localizedDescription
        }
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
