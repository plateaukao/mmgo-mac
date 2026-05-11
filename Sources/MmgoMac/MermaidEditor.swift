import SwiftUI
import AppKit

/// NSTextView-backed editor that applies Mermaid syntax highlighting.
struct MermaidEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.textBackgroundColor

        let tv = MermaidTextView(frame: .zero)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = NSColor.labelColor
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.drawsBackground = true
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.delegate = context.coordinator
        tv.string = text

        scroll.documentView = tv
        context.coordinator.highlight(tv)

        // Once the view is in a window, make it first responder so the user
        // can start typing immediately without an extra click.
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // Skip sync while the user is actively editing — external setters
        // (paste, history selection) blur the editor first so they still
        // reach this branch.
        if tv.string != text, tv.window?.firstResponder !== tv {
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
        var parent: MermaidEditor
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

/// NSTextView subclass that aggressively claims first-responder on click.
///
/// NavigationSplitView in SwiftUI sometimes interferes with the default
/// first-responder hand-off in the sidebar column, leaving the embedded
/// NSTextView visible but unfocusable. Overriding `mouseDown` and
/// `acceptsFirstResponder` ensures clicks always put the cursor in here.
private final class MermaidTextView: NSTextView {
    override var acceptsFirstResponder: Bool { isEditable }

    override func mouseDown(with event: NSEvent) {
        if let window, window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Initial focus once we are attached to a real window.
        if window != nil, window?.firstResponder !== self {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
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
