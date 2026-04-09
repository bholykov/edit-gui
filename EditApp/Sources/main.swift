import AppKit

let app = NSApplication.shared
// Must be set before app.run() — tells macOS this is a regular foreground
// app with a Dock icon and keyboard focus, even without a .app bundle.
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
