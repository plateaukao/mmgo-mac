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
      MermaidRenderer.swift
```

## Build the Go shared library

From `~/src/mmgo/`:

```bash
CGO_CFLAGS="-mmacosx-version-min=13.0" \
CGO_LDFLAGS="-mmacosx-version-min=13.0 -Wl,-install_name,@rpath/libmmgo.dylib" \
go build -buildmode=c-shared -o build/libmmgo.dylib ./cmd/mmgolib
```

The `min` flag pins the dylib's deployment target to match the Swift app
(macOS 13). The `-install_name` flag rewrites the dylib's recorded path
to `@rpath/libmmgo.dylib`, so the Swift executable's embedded rpath is
consulted at load time.

That produces `build/libmmgo.dylib` and `build/libmmgo.h`. The header is
already copied into `Sources/CMmgo/`; if you change the cgo signatures,
re-copy it:

```bash
cp ~/src/mmgo/build/libmmgo.h Sources/CMmgo/libmmgo.h
```

## Run the app

```bash
cd ~/src/mmgo-mac
swift run
```

If your `mmgo` checkout lives elsewhere:

```bash
MMGO_BUILD_DIR=/path/to/mmgo/build swift run
```

`Package.swift` embeds an `@rpath` entry pointing at `MMGO_BUILD_DIR`,
so the dylib is found at runtime without `DYLD_LIBRARY_PATH`.

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
