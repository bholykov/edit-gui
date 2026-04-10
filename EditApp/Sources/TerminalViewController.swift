import AppKit
import SwiftTerm

/// Hosts the MS Edit process inside a SwiftTerm terminal view and wires up
/// native macOS interactions (context menu, file pickers).
class TerminalViewController: NSViewController {

    private var terminalView: EditTerminalView!
    private var processStarted = false
    private var pendingOpenPath: String?
    private var eventMonitors: [Any] = []
    /// True while a drag or multi-click selection gesture is in progress.
    private var inSelectionMode = false

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
        terminalView = EditTerminalView(frame: view.bounds)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        terminalView.processDelegate = self

        guard let binary = editBinaryPath() else {
            showMissingBinaryError()
            return
        }
        terminalView.startProcess(executable: binary, args: args, execName: "edit")
        setupEventMonitors()
    }

    private func setupEventMonitors() {
        // Scroll wheel → PTY arrow keys.
        // SwiftTerm's scrollWheel (public, not open) routes delta to its scrollback
        // buffer, which is always empty for MS Edit (a full-screen TUI). We consume
        // the event here and send Up/Down arrow sequences to the PTY instead.
        addMonitor(for: .scrollWheel) { [weak self] event in
            guard let self, event.window == self.view.window,
                  event.deltaY != 0 else { return event }
            let lines = max(1, Int(abs(event.deltaY).rounded()))
            let appCursor = self.terminalView.terminal.applicationCursor
            let seq = event.deltaY > 0
                ? (appCursor ? "\u{1b}OA" : "\u{1b}[A")
                : (appCursor ? "\u{1b}OB" : "\u{1b}[B")
            for _ in 0..<lines { self.send(seq) }
            return nil  // consumed — don't pass to SwiftTerm's scrollback
        }

        // Text selection — bypass PTY mouse reporting (?1002) so SwiftTerm can
        // perform native selection. Three gestures enter selection mode:
        //   • Double-click (SwiftTerm word selection, then Cmd+C to copy)
        //   • Any drag (click-and-drag to select a range)
        //   • Shift+click (extend an existing selection)
        // Single clicks always pass through to the PTY (MS Edit cursor positioning).
        addMonitor(for: .leftMouseDown) { [weak self] event in
            guard let self, event.window == self.view.window else { return event }
            let isSelectionGesture = event.clickCount >= 2
                || event.modifierFlags.contains(.shift)
            if isSelectionGesture {
                self.inSelectionMode = true
                self.terminalView.allowMouseReporting = false
            } else {
                // Single click: pass to PTY, reset any previous selection state.
                self.inSelectionMode = false
            }
            return event
        }
        // Any drag (not just Shift-drag) starts SwiftTerm selection.
        // The preceding mouseDown may have already gone to the PTY (single click
        // before a drag), but that is acceptable — it only moves MS Edit's cursor.
        addMonitor(for: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            if !self.inSelectionMode {
                self.inSelectionMode = true
                self.terminalView.allowMouseReporting = false
            }
            return event
        }
        addMonitor(for: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            if self.inSelectionMode {
                self.inSelectionMode = false
                self.terminalView.allowMouseReporting = true
                // Keep terminal view as first responder so Cmd+C reaches SwiftTerm.
                self.view.window?.makeFirstResponder(self.terminalView)
            }
            return event
        }
    }

    private func addMonitor(for mask: NSEvent.EventTypeMask,
                            handler: @escaping (NSEvent) -> NSEvent?) {
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler) {
            eventMonitors.append(m)
        }
    }

    deinit {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
    }

    private func editBinaryPath() -> String? {
        // 1. Proper .app bundle (Resources/edit)
        if let bundled = Bundle.main.path(forResource: "edit", ofType: nil) {
            return bundled
        }
        // 2. SPM dev build: binary sits next to the EditApp executable
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        let devPath = execDir.appendingPathComponent("edit").path
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }
        return nil
    }

    // MARK: - Programmatic PTY input

    /// Sends a raw string to the MS Edit process via the PTY.
    func send(_ text: String) {
        terminalView.send(txt: text)
    }

    /// Opens a file by injecting Ctrl+P (Go to File) followed by the path.
    /// MS Edit's "Go to File" dialog accepts a typed path and confirms on Enter.
    /// If called before the process has started, the open is queued until ready.
    func open(path: String) {
        guard processStarted else {
            pendingOpenPath = path
            return
        }
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
    /// Explicitly copies SwiftTerm's current text selection to the clipboard.
    /// SwiftTerm's own copy: method is @objc open and IS in the responder chain,
    /// but calling it directly ensures it runs even if responder dispatch misroutes.
    @objc func menuCopy() { terminalView.copy(self) }

    @objc func menuNew()      { send("\u{0e}") }  // Ctrl+N
    @objc func menuSave()     { send("\u{13}") }  // Ctrl+S
    @objc func menuClose()    { send("\u{17}") }  // Ctrl+W
    @objc func menuUndo()     { send("\u{1a}") }  // Ctrl+Z
    @objc func menuRedo()     { send("\u{19}") }  // Ctrl+Y
    @objc func menuFind()     { send("\u{06}") }  // Ctrl+F
    @objc func menuReplace()  { send("\u{12}") }  // Ctrl+R
    @objc func menuGoToLine() { send("\u{07}") }  // Ctrl+G

    @objc func menuOpen() {
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
        // Use the first resize event as a signal that the process is live.
        if !processStarted {
            processStarted = true
            if let path = pendingOpenPath {
                pendingOpenPath = nil
                // Give MS Edit extra time to render its initial UI before injecting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.open(path: path)
                }
            }
        }
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        view.window?.title = title.isEmpty ? "Edit" : title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Not used by MS Edit.
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Only quit the app if edit exited cleanly (user closed it).
        // exitCode nil means the process never started — don't quit.
        guard exitCode != nil else { return }
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showMissingBinaryError() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "edit binary not found"
            alert.informativeText = """
                Build the MS Edit binary first, then copy it next to this executable:

                rsync -a --exclude='.git' --exclude='target' ~/edit-gui/ /tmp/edit-src/
                cd /tmp/edit-src && cargo build --release
                cp target/release/edit ~/edit-gui/EditApp/.build/debug/edit
                """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }
}
