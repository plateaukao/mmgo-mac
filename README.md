# mmgo-mac

A small SwiftUI macOS app that renders Mermaid diagrams. The renderer is
[Mermaid.js](https://github.com/mermaid-js/mermaid) itself, bundled into
the app and hosted in an off-screen `WKWebView`.

The repo is named after [`mmgo`](https://github.com/julianshen/mmgo),
which was the original rendering backend; see the git history before
commit `250034b` if you need that variant.

## Features

- Live preview that re-renders on every keystroke (with an in-flight
  collapsing queue so bursts don't pile up).
- Syntax-highlighted Mermaid editor (`NSTextView`-backed).
- Theme switcher: default / dark / forest / neutral.
- History popover (last 15 diagrams); editing an existing diagram
  replaces its slot instead of stacking new entries.
- Copy PNG / Save PNG… from the rendered output.
- Self-contained `.app` — no Node, no headless browser, no external
  dylibs.

## Layout

```
~/src/mmgo-mac/
  Package.swift
  Sources/
    MmgoMac/
      MmgoMacApp.swift
      ContentView.swift
      MermaidEditor.swift
      Resources/
        mermaid.min.js     # bundled mermaid v11
        mermaid.html       # host page evaluated in WKWebView
```

## Run the app

```bash
cd ~/src/mmgo-mac
swift run
```

No external dependencies — `mermaid.min.js` is a SwiftPM resource and is
loaded via `Bundle.module` at startup.

## Using the app

- The left pane is a Mermaid editor (pre-filled with a sample flowchart).
- Click **Paste** to replace the editor contents with the clipboard.
- Pick a theme; the right pane re-renders on every edit.
- The history popover keeps the last 15 distinct diagrams. Editing an
  existing diagram replaces its history slot rather than stacking new
  entries on top.
- Toolbar **Copy PNG** / **Save PNG…** snapshot the rendered diagram.

## Packaging as a .app bundle

```bash
./build.sh
open dist/Mmgo.app
```

`build.sh` runs `swift build -c release`, assembles `dist/Mmgo.app` with
the binary in `Contents/MacOS/` and the SwiftPM resource bundle (which
contains `mermaid.min.js` + `mermaid.html`) in `Contents/Resources/`, and
ad-hoc codesigns the result.

## Updating Mermaid

To pull a newer mermaid release:

```bash
curl -fL -o Sources/MmgoMac/Resources/mermaid.min.js \
  https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js
```

## Acknowledgements

The rendering work — parsing, graph layout, text measurement, SVG
generation — is done by [Mermaid.js](https://github.com/mermaid-js/mermaid).
This project is a thin SwiftUI shell around it.
