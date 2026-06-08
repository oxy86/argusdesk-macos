import AppKit

// ArgusDesk currently uses a minimal AppKit application entry point instead of
// the SwiftUI `App` protocol because the app needs direct control over the
// overlay-style window and activation policy.
let app = NSApplication.shared
let delegate = AppDelegate()

// `.accessory` keeps ArgusDesk out of the Dock while still allowing it to own a
// window. This matches the desktop-companion direction for the project.
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
