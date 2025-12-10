//
//  AppDelegate.swift
//  EditMac
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var editorViewController: EditorViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✓ App launched")

        let contentRect = NSRect(x: 0, y: 0, width: 1024, height: 768)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        print("✓ Window created")

        window.title = "Edit"
        window.center()

        print("✓ Creating EditorViewController...")
        editorViewController = EditorViewController()
        print("✓ EditorViewController created")

        window.contentViewController = editorViewController

        createMenuBar()
        print("✓ Menu bar created")

        window.makeKeyAndOrderFront(nil)
        print("✓ Window should be visible now")
    }

    func applicationWillTerminate(_ notification: Notification) {
        editorViewController.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func createMenuBar() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(title: "About Edit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Edit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "File"
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(NSMenuItem(title: "New", action: #selector(editorViewController.newFile(_:)), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Open...", action: #selector(editorViewController.openFile(_:)), keyEquivalent: "o"))

        // Recent files submenu
        let recentMenuItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenuItem.submenu = recentMenu
        fileMenu.addItem(recentMenuItem)

        // Add "Clear Menu" item to recent files
        recentMenu.addItem(NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: ""))

        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Save", action: #selector(editorViewController.saveFile(_:)), keyEquivalent: "s"))
        fileMenu.addItem(NSMenuItem(title: "Save As...", action: #selector(editorViewController.saveFileAs(_:)), keyEquivalent: "S"))

        // Edit menu
        let editMenuItem = NSMenuItem()
        editMenuItem.title = "Edit"
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(editorViewController.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(editorViewController.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(editorViewController.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Clear", action: #selector(editorViewController.clear(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(editorViewController.selectAllText(_:)), keyEquivalent: "a"))

        NSApplication.shared.mainMenu = mainMenu
    }
}
