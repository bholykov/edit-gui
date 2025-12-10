//
//  EditorViewController.swift
//  EditMac
//

import Cocoa

class EditorViewController: NSViewController {

    var editView: EditView!

    override func loadView() {
        print("  → loadView() called")
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        editView = EditView(frame: frame)

        self.view = editView
        print("  ✓ EditView created")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        print("  → viewDidLoad() called")
        view.window?.makeFirstResponder(view)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        print("  → viewDidAppear() called")
        print("  → Starting Edit...")
        editView.start()
        print("  ✓ Edit started")
    }

    @objc func newFile(_ sender: Any?) {
        editView.newFile()
    }

    @objc func openFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a file to open"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.editView.openFile(path: url.path)
            }
        }
    }

    @objc func saveFile(_ sender: Any?) {
        editView.saveFile()
    }

    @objc func saveFileAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.message = "Save file as"
        panel.nameFieldStringValue = "Untitled.txt"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.editView.saveFileAs(path: url.path)
            }
        }
    }

    @objc func cut(_ sender: Any?) {
        editView.cut()
    }

    @objc func copy(_ sender: Any?) {
        editView.copy()
    }

    @objc func paste(_ sender: Any?) {
        editView.paste()
    }

    @objc func clear(_ sender: Any?) {
        editView.clear()
    }

    @objc func selectAll(_ sender: Any?) {
        editView.selectAll()
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    func cleanup() {
        editView.cleanup()
    }
}
