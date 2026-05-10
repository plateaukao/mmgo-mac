# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & run

```bash
swift build        # compile
swift run          # build and launch the SwiftUI app
```

There is no test target. Lint/format tools are not configured.

The app links against `Frameworks/libmmgo.dylib`, which is **bundled in the repo** (arm64, macOS 14+). The default `MMGO_BUILD_DIR` in `Package.swift` resolves to `<package>/Frameworks` via `#filePath`, so a fresh checkout builds without external dependencies. To use a fresher build from a sibling `mmgo` checkout:

```bash
MMGO_BUILD_DIR=/path/to/mmgo/build swift run
```

If you regenerate the dylib, the deployment-target pin (`-mmacosx-version-min=14.0`) and `-install_name @rpath/libmmgo.dylib` are both load-bearing. Building the dylib without `@rpath` install_name will make `swift run` fail at load time even if linking succeeds.

If cgo signatures change in `mmgo`, copy the regenerated header back in:

```bash
cp ~/src/mmgo/build/libmmgo.h Sources/CMmgo/libmmgo.h
```

## Architecture

Three-layer stack, all small:

1. **`Sources/CMmgo/`** — `systemLibrary` SwiftPM target. `module.modulemap` exposes `libmmgo.h` as the `CMmgo` Swift module and declares `link "mmgo"`. The actual `-L`/`-lmmgo`/`-rpath` flags are in `Package.swift` (not the modulemap), because the dylib path is resolved at package-load time from `MMGO_BUILD_DIR`.

2. **`MermaidRenderer.swift`** — the only file that touches C. Wraps `MmgoRenderSVG` / `MmgoFree`. Every C string returned by mmgo (success result *and* error message via the `errOut` out-param) is malloc'd on the Go side and **must** be released with `MmgoFree`; the wrapper does this in `defer`/explicit calls. Don't pass Swift `String` pointers through without going through `withCString` — Go retains nothing.

3. **SwiftUI layer** (`MmgoMacApp`, `ContentView`, `MermaidEditor`, `SVGView`):
   - `ContentView` re-renders on **every** keystroke via `.onChange(of: source)`. There is no debounce — mmgo is fast enough that this is fine for typical diagrams, but be aware before adding heavy work to the render path.
   - `MermaidEditor` is an `NSTextView`-backed `NSViewRepresentable` (SwiftUI's `TextEditor` is used only because we need syntax highlighting). Highlighting runs synchronously in `textDidChange` over the full document with regex rules in `MermaidHighlight.rules`.
   - `SVGView` is a `WKWebView` that reloads HTML on every update. The SVG is embedded directly into an inline HTML document; it is not sandboxed against script-bearing SVGs (mmgo output is trusted).

## Packaging

`swift run` produces a CLI-style executable in `.build/`, not a `.app`. Shipping a real bundle requires an Xcode project that copies `libmmgo.dylib` into `Contents/Frameworks` and sets the rpath to `@executable_path/../Frameworks` — see README "Packaging as a .app bundle".
