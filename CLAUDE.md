# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & run

```bash
swift build        # compile
swift run          # build and launch the SwiftUI app
./build.sh         # produce a self-contained dist/Mmgo.app
```

There is no test target. Lint/format tools are not configured.

The app bundles `mermaid.min.js` (v11) and `mermaid.html` as SwiftPM
resources under `Sources/MmgoMac/Resources/`. They are loaded at runtime
via `Bundle.module`. There is no external dylib or C dependency.

To update mermaid:

```bash
curl -fL -o Sources/MmgoMac/Resources/mermaid.min.js \
  https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js
```

## Architecture

Two layers:

1. **`Sources/MmgoMac/Resources/mermaid.html`** — host page loaded once
   into a `WKWebView`. Includes `mermaid.min.js` via a relative `<script
   src>` and exposes a global `renderMermaid(source, theme)` that calls
   `mermaid.render()` and posts the resulting SVG (or error) back to
   Swift through `window.webkit.messageHandlers.mermaid`. After each
   render it sweeps any leftover `[id^="d"]` divs from `<body>` —
   mermaid.js sometimes leaks a temporary measurement node on parse
   error, which would otherwise stack up as multiple "Syntax error"
   views in the page.

2. **SwiftUI layer** (`MmgoMacApp`, `ContentView`, `MermaidEditor`):
   - `MermaidWebView` (defined inside `ContentView.swift`) owns the
     `WKWebView`, the navigation delegate, and the script-message
     handler. It exposes `render(source:theme:)` which forwards to JS
     via `evaluateJavaScript`. A single-slot pending queue collapses
     bursts of keystrokes: at most one render in flight plus the latest
     desired state.
   - `ContentView` re-renders on every keystroke via `.onChange(of:
     source)`. The web view's `@Published` `svg` and `errorMessage`
     drive the UI. The pending-queue inside `MermaidWebView` is what
     keeps this from piling up — there is no time-based debounce.
   - `MermaidEditor` is an `NSTextView`-backed `NSViewRepresentable`
     (SwiftUI's `TextEditor` is bypassed because we need syntax
     highlighting). Highlighting runs synchronously in `textDidChange`
     over the full document with regex rules in `MermaidHighlight.rules`.
   - History: editing an existing entry replaces its slot rather than
     stacking up new entries. `ContentView` tracks the active baseline
     in `editingOriginal`; `addToHistory` removes it before inserting
     the new version, so one diagram in progress = one history slot.
     Pasting clears the baseline (the pasted text becomes a fresh
     entry on its first save).
   - PNG export (`Copy PNG`, `Save PNG…`) uses `WKWebView.takeSnapshot`
     on the same web view that's showing the diagram.

## Packaging

`build.sh` runs `swift build -c release`, assembles `dist/Mmgo.app` with
the binary in `Contents/MacOS/` and the SwiftPM resource bundle
(`MmgoMac_MmgoMac.bundle`, which holds `mermaid.min.js` + `mermaid.html`)
in `Contents/Resources/`, writes `Info.plist`, and ad-hoc codesigns the
result.

The resource bundle must live in `Contents/Resources/`, not
`Contents/MacOS/`: `Bundle.module` searches both, but a sub-bundle in
`Contents/MacOS/` looks like a malformed helper to `codesign --deep` and
breaks signing.
