import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        windowController = MainWindowController()
        windowController?.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        windowController?.open(path: filename)
        return true
    }

    // MARK: - Menu bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu — first item is always the application menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(
            title: "Quit EditApp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        mainMenu.addItem(buildFileMenu())
        mainMenu.addItem(buildEditMenu())
        mainMenu.addItem(buildViewMenu())

        NSApp.mainMenu = mainMenu
    }

    private func buildFileMenu() -> NSMenuItem {
        let top = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "File")
        menu.addItem(mi("New",    "n", #selector(TerminalViewController.menuNew)))
        menu.addItem(mi("Open…",  "o", #selector(TerminalViewController.menuOpen)))
        menu.addItem(.separator())
        menu.addItem(mi("Save",   "s", #selector(TerminalViewController.menuSave)))
        menu.addItem(mi("Close",  "w", #selector(TerminalViewController.menuClose)))
        top.submenu = menu
        return top
    }

    private func buildEditMenu() -> NSMenuItem {
        let top = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")
        menu.addItem(mi("Undo",       "z", #selector(TerminalViewController.menuUndo)))
        // Cmd+Shift+Z: uppercase keyEquivalent adds the Shift modifier automatically
        menu.addItem(mi("Redo",       "Z", #selector(TerminalViewController.menuRedo)))
        menu.addItem(.separator())
        menu.addItem(mi("Cut",        "x", #selector(TerminalViewController.menuCut)))
        // menuCopy calls terminalView.copy() directly so SwiftTerm's selection text is used.
        menu.addItem(mi("Copy",       "c", #selector(TerminalViewController.menuCopy)))
        menu.addItem(mi("Paste",      "v", #selector(TerminalViewController.menuPaste)))
        menu.addItem(mi("Select All", "a", #selector(TerminalViewController.menuSelectAll)))
        menu.addItem(.separator())
        menu.addItem(mi("Find…",           "f", #selector(TerminalViewController.menuFind)))
        // Cmd+Option+F for Find & Replace (Cmd+H is reserved by macOS for Hide Window)
        let replaceItem = mi("Find & Replace…", "f", #selector(TerminalViewController.menuReplace))
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(replaceItem)
        menu.addItem(mi("Go to Line…",     "l", #selector(TerminalViewController.menuGoToLine)))
        top.submenu = menu
        return top
    }

    private func buildViewMenu() -> NSMenuItem {
        let top = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "View")
        // Word Wrap toggle: MS Edit shortcut is Alt+Z (sent as ESC z over PTY)
        let wrapItem = mi("Word Wrap", "z", #selector(TerminalViewController.menuWordWrap))
        wrapItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(wrapItem)
        menu.addItem(.separator())
        menu.addItem(mi("Go to File…", "p", #selector(TerminalViewController.menuGoToFile)))
        top.submenu = menu
        return top
    }

    /// Creates a menu item that targets `nil` so the responder chain dispatches it.
    private func mi(_ title: String, _ key: String, _ action: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
