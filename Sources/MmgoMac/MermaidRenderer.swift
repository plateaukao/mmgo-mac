import Foundation
import CMmgo

/// Swift wrapper around the mmgo C-shared library.
enum MermaidRenderer {
    enum RenderError: Error, LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .failed(let msg): return msg
            }
        }
    }

    /// Render Mermaid `source` into an SVG string.
    /// - Parameters:
    ///   - source: Mermaid diagram text.
    ///   - theme: optional theme name (e.g. "default", "dark", "forest", "neutral").
    ///   - background: optional background color (e.g. "white", "transparent", "#fff").
    static func renderSVG(
        source: String,
        theme: String? = nil,
        background: String? = nil
    ) throws -> String {
        return try source.withCString { srcPtr in
            try withOptionalCString(theme) { themePtr in
                try withOptionalCString(background) { bgPtr in
                    var errPtr: UnsafeMutablePointer<CChar>? = nil
                    let resultPtr = MmgoRenderSVG(
                        UnsafeMutablePointer(mutating: srcPtr),
                        UnsafeMutablePointer(mutating: themePtr),
                        UnsafeMutablePointer(mutating: bgPtr),
                        &errPtr
                    )

                    if let resultPtr = resultPtr {
                        defer { MmgoFree(resultPtr) }
                        return String(cString: resultPtr)
                    }

                    let message: String
                    if let errPtr = errPtr {
                        message = String(cString: errPtr)
                        MmgoFree(errPtr)
                    } else {
                        message = "unknown render error"
                    }
                    throw RenderError.failed(message)
                }
            }
        }
    }

    private static func withOptionalCString<R>(
        _ s: String?,
        _ body: (UnsafePointer<CChar>?) throws -> R
    ) rethrows -> R {
        if let s = s {
            return try s.withCString { try body($0) }
        }
        return try body(nil)
    }
}
