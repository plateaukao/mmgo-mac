# mmgo-mac

A small SwiftUI macOS app that renders Mermaid diagrams using the
[`mmgo`](https://github.com/julianshen/mmgo) Go library, linked as a
C-shared library (`libmmgo.dylib`).

## Layout

```
~/src/mmgo/                 # the Go library (sibling repo)
~/src/mmgo-mac/             # this app
  Package.swift
  Sources/
    CMmgo/                  # systemLibrary target wrapping libmmgo.h
      libmmgo.h
      module.modulemap
    MmgoMac/                # SwiftUI app
      MmgoMacApp.swift
      ContentView.swift
      MermaidEditor.swift
      MermaidRenderer.swift
```

## Run the app

```bash
cd ~/src/mmgo-mac
swift run
```

A prebuilt `Frameworks/libmmgo.dylib` (arm64, macOS 14+) is bundled in
the repo, so no separate `mmgo` checkout is needed for a default build.
`Package.swift` embeds an `@rpath` entry pointing at `Frameworks/`, so
the dylib is found at runtime without `DYLD_LIBRARY_PATH`.

## Rebuilding the Go shared library (optional)

If you have a local [`mmgo`](https://github.com/julianshen/mmgo) checkout
and want a fresher build, rebuild the dylib from there:

```bash
cd ~/src/mmgo
CGO_CFLAGS="-mmacosx-version-min=14.0" \
CGO_LDFLAGS="-mmacosx-version-min=14.0 -Wl,-install_name,@rpath/libmmgo.dylib" \
go build -buildmode=c-shared -o build/libmmgo.dylib ./cmd/mmgolib
```

The `min` flag pins the dylib's deployment target to match the Swift app
(macOS 14). The `-install_name` flag rewrites the dylib's recorded path
to `@rpath/libmmgo.dylib`, so the Swift executable's embedded rpath is
consulted at load time.

Then either copy the result into `Frameworks/` or point at it via env var:

```bash
cp ~/src/mmgo/build/libmmgo.dylib Frameworks/libmmgo.dylib
# or:
MMGO_BUILD_DIR=/path/to/mmgo/build swift run
```

If the cgo signatures changed, re-copy the header too:

```bash
cp ~/src/mmgo/build/libmmgo.h Sources/CMmgo/libmmgo.h
```

## Using the app

- The left pane is a Mermaid editor (pre-filled with a sample flowchart).
- Click **Paste** to replace the editor contents with the clipboard.
- Pick a theme; the right pane re-renders on every edit.
- ⌘↩ forces a re-render.

## Packaging as a .app bundle

`swift run` produces a CLI-style executable, not a `.app`. To ship a
proper bundle, create a small Xcode project, add `Sources/MmgoMac/*.swift`
to it, link `libmmgo.dylib`, copy it into `Contents/Frameworks`, and set
`@rpath` to `@executable_path/../Frameworks`.

## Acknowledgements

All of the actual rendering work — Mermaid parsing, graph layout, font-based
text measurement, and SVG generation — is done by
[**mmgo**](https://github.com/julianshen/mmgo) by
[@julianshen](https://github.com/julianshen). This project is just a thin
SwiftUI shell around its C-shared-library build target. Big thanks to the
mmgo authors for making a Mermaid renderer that ships as a single static
binary with no Node.js or headless-browser dependency — without that,
this app wouldn't exist.

mmgo itself stands on the shoulders of:

- The [Mermaid](https://github.com/mermaid-js/mermaid) project, which
  defines the diagram syntax this app accepts.
- [dagre](https://github.com/dagrejs/dagre), whose graph layout
  algorithms mmgo ports to Go.
