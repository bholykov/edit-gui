import AppKit

class MainWindowController: NSWindowController {

    private var terminalVC: TerminalViewController!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit"
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        self.init(window: window)

        terminalVC = TerminalViewController()
        window.contentViewController = terminalVC
    }

    func open(path: String) {
        terminalVC.open(path: path)
    }
}
