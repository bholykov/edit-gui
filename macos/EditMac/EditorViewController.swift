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
        // TODO: Wire up to Edit
    }

    @objc func openFile(_ sender: Any?) {
        // TODO: Wire up to Edit
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    func cleanup() {
        editView.cleanup()
    }
}
