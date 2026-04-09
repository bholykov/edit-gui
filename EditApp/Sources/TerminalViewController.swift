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

    private func setupTerminal() {
        terminalView = LocalProcessTerminalView(frame: view.bounds)
        terminalView.autoresizingMask = [.width, .height]
        view.addSubview(terminalView)

        terminalView.processDelegate = self

        let binary = editBinaryPath()
        terminalView.startProcess(executable: binary, execName: "edit", args: [binary])
    }

    private func editBinaryPath() -> String {
        // Prefer the binary bundled in Resources; fall back to PATH for dev builds.
        if let bundled = Bundle.main.path(forResource: "edit", ofType: nil) {
            return bundled
        }
        return "/usr/local/bin/edit"
    }

    // MARK: - Programmatic input

    /// Sends a raw string to the MS Edit process via the PTY.
    func send(_ text: String) {
        terminalView.send(txt: text)
    }

    /// Sends a file path to the running process by injecting Ctrl+O followed
    /// by the path and Enter — relies on MS Edit's built-in open flow.
    func open(path: String) {
        send("\u{0f}")               // Ctrl+O — triggers MS Edit's open dialog
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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

        menu.addItem(item("New",        action: #selector(menuNew)))
        menu.addItem(item("Open…",      action: #selector(menuOpen)))
        menu.addItem(.separator())
        menu.addItem(item("Save",       action: #selector(menuSave)))
        menu.addItem(item("Save As…",   action: #selector(menuSaveAs)))
        menu.addItem(item("Close",      action: #selector(menuClose)))
        menu.addItem(.separator())
        menu.addItem(item("Undo",       action: #selector(menuUndo)))
        menu.addItem(item("Redo",       action: #selector(menuRedo)))
        menu.addItem(.separator())
        menu.addItem(item("Find…",      action: #selector(menuFind)))
        menu.addItem(item("Replace…",   action: #selector(menuReplace)))

        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Menu actions — File

    @objc private func menuNew()   { send("\u{0e}") }  // Ctrl+N
    @objc private func menuSave()  { send("\u{13}") }  // Ctrl+S
    @objc private func menuClose() { send("\u{17}") }  // Ctrl+W

    @objc private func menuOpen() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(path: url.path)
        }
    }

    @objc private func menuSaveAs() {
        let panel = NSSavePanel()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            // Ctrl+Shift+S, then type the path and confirm
            self?.send("\u{13}")       // Ctrl+S triggers Save As when no path set
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.send(url.path + "\r")
            }
        }
    }

    // MARK: - Menu actions — Edit

    @objc private func menuUndo()    { send("\u{1a}") }  // Ctrl+Z
    @objc private func menuRedo()    { send("\u{19}") }  // Ctrl+Y
    @objc private func menuFind()    { send("\u{06}") }  // Ctrl+F
    @objc private func menuReplace() { send("\u{12}") }  // Ctrl+R
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalViewController: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Nothing extra needed — SwiftTerm propagates SIGWINCH automatically.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        view.window?.title = title.isEmpty ? "Edit" : title
    }

    func processTerminated(source: LocalProcessTerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
