import AppKit
import SwiftTerm

/// Hosts the MS Edit process inside a SwiftTerm terminal view and wires up
/// native macOS interactions (context menu, file pickers).
class TerminalViewController: NSViewController {

    private var terminalView: LocalProcessTerminalView!

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTerminal()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(terminalView)
    }

    // MARK: - Terminal setup

    private func setupTerminal(args: [String] = []) {
        terminalView = LocalProcessTerminalView(frame: view.bounds)
        terminalView.autoresizingMask = [.width, .height]
        view.addSubview(terminalView)

        terminalView.processDelegate = self

        let binary = editBinaryPath()
        terminalView.startProcess(executable: binary, args: args, execName: "edit")
    }

    private func editBinaryPath() -> String {
        // Prefer the binary bundled in Resources; fall back to PATH for dev builds.
        if let bundled = Bundle.main.path(forResource: "edit", ofType: nil) {
            return bundled
        }
        return "/usr/local/bin/edit"
    }

    // MARK: - Programmatic PTY input

    /// Sends a raw string to the MS Edit process via the PTY.
    func send(_ text: String) {
        terminalView.send(txt: text)
    }

    /// Opens a file by injecting Ctrl+P (Go to File) followed by the path.
    /// MS Edit's "Go to File" dialog accepts a typed path and confirms on Enter.
    func open(path: String) {
        send("\u{10}")  // Ctrl+P — opens Go to File dialog
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.send(path + "\r")
        }
    }

    // MARK: - Context menu

    override func rightMouseDown(with event: NSEvent) {
        let menu = buildContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "")

        menu.addItem(item("New",          action: #selector(menuNew)))
        menu.addItem(item("Open…",        action: #selector(menuOpen)))
        menu.addItem(.separator())
        menu.addItem(item("Save",         action: #selector(menuSave)))
        menu.addItem(item("Close",        action: #selector(menuClose)))
        menu.addItem(.separator())
        menu.addItem(item("Undo",         action: #selector(menuUndo)))
        menu.addItem(item("Redo",         action: #selector(menuRedo)))
        menu.addItem(.separator())
        menu.addItem(item("Find…",        action: #selector(menuFind)))
        menu.addItem(item("Replace…",     action: #selector(menuReplace)))
        menu.addItem(item("Go to Line…",  action: #selector(menuGoToLine)))

        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Menu actions

    // Ctrl codes 0x01–0x1A map directly to Ctrl+A through Ctrl+Z in MS Edit's
    // input parser (src/input.rs: the `..='\x1a'` arm shifts the byte to A–Z).
    @objc private func menuNew()      { send("\u{0e}") }  // Ctrl+N
    @objc private func menuSave()     { send("\u{13}") }  // Ctrl+S
    @objc private func menuClose()    { send("\u{17}") }  // Ctrl+W
    @objc private func menuUndo()     { send("\u{1a}") }  // Ctrl+Z
    @objc private func menuRedo()     { send("\u{19}") }  // Ctrl+Y
    @objc private func menuFind()     { send("\u{06}") }  // Ctrl+F
    @objc private func menuReplace()  { send("\u{12}") }  // Ctrl+R
    @objc private func menuGoToLine() { send("\u{07}") }  // Ctrl+G

    @objc private func menuOpen() {
        // Show a native file picker, then inject the path via Go to File (Ctrl+P).
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(path: url.path)
        }
    }

    // Note: Save As (Ctrl+Shift+S) is intentionally absent from the context menu.
    // Ctrl+Shift+S is not distinguishable from Ctrl+S over a PTY on macOS — the
    // CTRL_SHIFT modifier only works via the Windows console API. Users can access
    // Save As through MS Edit's own TUI menu bar (which is mouse-clickable via
    // the ?1002 mouse reporting MS Edit enables at startup).
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalViewController: LocalProcessTerminalViewDelegate {

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm propagates SIGWINCH automatically; nothing extra needed.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        view.window?.title = title.isEmpty ? "Edit" : title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Not used by MS Edit.
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
