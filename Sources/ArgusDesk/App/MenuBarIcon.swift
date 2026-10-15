import AppKit

/// Loads the menu bar status icon from bundle resources.
///
/// Tries `menubar-icon@2x.png` (44×44) first, then `menubar-icon.png` (22×22).
/// Falls back to an SF Symbol circle if neither is found.
@MainActor
enum MenuBarIcon {
    /// The cached NSImage used by the SwiftUI MenuBarExtra label.
    static let image: NSImage = {
        // Strategy 1: standard Bundle.main lookup.
        if let url = Bundle.main.url(forResource: "menubar-icon@2x", withExtension: "png")
            ?? Bundle.main.url(forResource: "menubar-icon", withExtension: "png") {
            if let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                return img
            }
        }

        // Strategy 2: look next to the executable.
        let execDir = Bundle.main.bundleURL.deletingLastPathComponent()
        for name in ["menubar-icon@2x.png", "menubar-icon.png"] {
            let url = execDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                return img
            }
        }

        // Fallback: SF Symbol circle.
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "ArgusDesk")!
    }()
}
