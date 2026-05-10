import SwiftUI
import AppKit

/// NSTextView-backed editor that applies Mermaid syntax highlighting.
struct MermaidEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.allowsUndo = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.delegate = context.coordinator
        tv.string = text
        context.coordinator.highlight(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            let safe = NSRange(
                location: min(sel.location, tv.string.utf16.count),
                length: 0
            )
            tv.setSelectedRange(safe)
            context.coordinator.highlight(tv)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MermaidEditor
        init(_ parent: MermaidEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv)
        }

        func highlight(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let nsString = tv.string as NSString
            let full = NSRange(location: 0, length: nsString.length)
            let font = tv.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

            storage.beginEditing()
            storage.setAttributes(
                [.foregroundColor: NSColor.labelColor, .font: font],
                range: full
            )
            for rule in MermaidHighlight.rules {
                rule.regex.enumerateMatches(in: tv.string, options: [], range: full) { match, _, _ in
                    guard let r = match?.range, r.location != NSNotFound else { return }
                    storage.addAttribute(.foregroundColor, value: rule.color, range: r)
                }
            }
            storage.endEditing()
        }
    }
}

enum MermaidHighlight {
    struct Rule {
        let regex: NSRegularExpression
        let color: NSColor
    }

    static let rules: [Rule] = {
        func r(_ pattern: String, _ color: NSColor) -> Rule {
            // swiftlint:disable:next force_try
            Rule(regex: try! NSRegularExpression(pattern: pattern), color: color)
        }
        return [
            // %% line comments
            r("%%[^\\n]*", .systemGray),
            // "double-quoted strings"
            r("\"[^\"\\n]*\"", .systemBrown),
            // diagram-type keywords at line start
            r("""
              (?m)^\\s*(flowchart|graph|sequenceDiagram|classDiagram|\
              stateDiagram(?:-v2)?|erDiagram|gantt|pie|journey|gitGraph|\
              mindmap|timeline|quadrantChart|requirementDiagram|\
              C4Context|C4Container|C4Component|C4Dynamic|C4Deployment|\
              sankey-beta|xychart-beta|block-beta|kanban|\
              architecture-beta|packet-beta)\\b
              """, .systemPurple),
            // direction
            r("\\b(LR|RL|TB|TD|BT)\\b", .systemPurple),
            // structural / control keywords
            r("""
              \\b(subgraph|end|style|classDef|class|click|link|linkStyle|\
              direction|loop|alt|else|opt|par|and|note|Note|activate|\
              deactivate|participant|actor|autonumber|rect|critical|break)\\b
              """, .systemBlue),
            // arrows / connectors: runs of - = . < > optionally followed by x or o
            r("[-=.<>]{2,}[xo]?", .systemRed),
            // numbers
            r("\\b\\d+(?:\\.\\d+)?\\b", .systemTeal),
        ]
    }()
}
