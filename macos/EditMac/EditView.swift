import Cocoa

class EditView: NSView {
    private var editState: OpaquePointer?
    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let cellSize = CGSize(width: 9, height: 18)

    // MS-DOS Edit color scheme
    private let dosBlue = NSColor(red: 0, green: 0, blue: 0.667, alpha: 1)  // #0000AA
    private let dosText = NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)  // Light gray
    private let dosMenuBg = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)  // Gray
    private let dosMenuText = NSColor.black
    private let menuBarHeight: CGFloat = 20
    private let statusBarHeight: CGFloat = 20

    // Cursor state
    private var cursorVisible = true
    private var cursorBlinkTimer: Timer?

    // Menu state
    private var activeMenu: Int? = nil  // Index of open menu (nil = none)
    private var menuRects: [NSRect] = []  // Clickable rects for each menu
    private let menuItems = [
        MenuItem(title: "File", items: ["New", "Open...", "Save", "Save As...", "---", "Exit"]),
        MenuItem(title: "Edit", items: ["Cut", "Copy", "Paste", "Clear"]),
        MenuItem(title: "Search", items: ["Find...", "Repeat Last Find", "Replace..."]),
        MenuItem(title: "Options", items: ["Display...", "Help Path..."]),
        MenuItem(title: "Help", items: ["Getting Started", "About..."])
    ]

    // File management
    private var currentFilePath: String?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    override var isFlipped: Bool {
        return true  // Use top-left origin for easier text drawing
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // wantsLayer = true  // DISABLED - causes draw() to not display properly

        // Register for drag & drop
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    func start() {
        let width = Int32(bounds.width)
        let height = Int32(bounds.height)

        print("    → Calling edit_init(\(width), \(height))...")
        editState = edit_init(width, height)

        if editState == nil {
            print("    ✗ FATAL: edit_init returned nil")
            fatalError("Failed to initialize Edit")
        }
        print("    ✓ Edit state initialized successfully")

        // Start cursor blink timer
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.cursorVisible.toggle()
            self?.setNeedsDisplay(self?.bounds ?? .zero)
        }

        setNeedsDisplay(bounds)
    }

    func cleanup() {
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil

        stopFileMonitoring()

        if let state = editState {
            edit_destroy(state)
            editState = nil
        }
    }

    // MARK: - File Operations

    func newFile() {
        guard let state = editState else { return }
        edit_new_file(state)
        currentFilePath = nil
        setNeedsDisplay(bounds)
    }

    func openFile(path: String) {
        guard let state = editState else { return }
        path.withCString { cPath in
            edit_open_file(state, cPath)
        }
        currentFilePath = path
        window?.title = "Edit - \((path as NSString).lastPathComponent)"

        // Start file monitoring
        startFileMonitoring(path: path)

        // Add to recent files
        NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: path))

        setNeedsDisplay(bounds)
    }

    func saveFile() {
        guard let state = editState else { return }

        if let path = currentFilePath {
            // Save to existing file
            path.withCString { cPath in
                edit_save_file_as(state, cPath)
            }
        } else {
            // No file path, trigger Save As
            if let controller = window?.windowController?.document as? NSDocument {
                controller.runModalSavePanel(for: .saveOperation, delegate: self, didSave: nil, contextInfo: nil)
            }
        }
    }

    func saveFileAs(path: String) {
        guard let state = editState else { return }
        path.withCString { cPath in
            edit_save_file_as(state, cPath)
        }
        currentFilePath = path
        window?.title = "Edit - \((path as NSString).lastPathComponent)"

        // Start file monitoring for the new file
        startFileMonitoring(path: path)

        // Add to recent files
        NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: path))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let state = editState else { return }

        // Fill with DOS blue background
        dosBlue.setFill()
        bounds.fill()

        // Draw menu bar at top
        dosMenuBg.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: menuBarHeight).fill()

        let menuAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dosMenuText
        ]

        // Draw menu titles and save their rects
        menuRects.removeAll()
        var menuX: CGFloat = 5
        for (index, menu) in menuItems.enumerated() {
            let width = CGFloat(menu.title.count * 9) + 10
            let rect = NSRect(x: menuX, y: 0, width: width, height: menuBarHeight)
            menuRects.append(rect)

            // Highlight if active
            if activeMenu == index {
                NSColor.black.setFill()
                rect.fill()
                let highlightAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white
                ]
                let menuStr = NSAttributedString(string: menu.title, attributes: highlightAttrs)
                menuStr.draw(at: CGPoint(x: menuX + 5, y: 2))
            } else {
                let menuStr = NSAttributedString(string: menu.title, attributes: menuAttrs)
                menuStr.draw(at: CGPoint(x: menuX + 5, y: 2))
            }

            menuX += width + 5
        }

        // Draw dropdown menu if one is active
        if let activeIndex = activeMenu, activeIndex < menuItems.count {
            drawDropdownMenu(at: activeIndex)
        }

        // Get cursor position
        var cursorRow: Int32 = 0
        var cursorCol: Int32 = 0
        edit_get_cursor_pos(state, &cursorRow, &cursorCol)

        // Draw status bar at bottom with real cursor position
        dosMenuBg.setFill()
        NSRect(x: 0, y: bounds.height - statusBarHeight, width: bounds.width, height: statusBarHeight).fill()

        let statusText = String(format: " Line %d   Col %d   F1=Help", cursorRow + 1, cursorCol + 1)
        let statusStr = NSAttributedString(string: statusText, attributes: menuAttrs)
        statusStr.draw(at: CGPoint(x: 5, y: bounds.height - statusBarHeight + 2))

        // Fast path: Get text content directly instead of iterating cells
        // Update the cache first to ensure we have fresh data
        edit_update_text_cache(state)

        let textLen = edit_get_text_length(state)
        guard textLen > 0 else { return }

        guard let textPtr = edit_get_text_content(state) else { return }

        let textData = Data(bytes: textPtr, count: Int(textLen))
        guard let text = String(data: textData, encoding: .utf8) else { return }

        // Draw text line by line (in the content area between menu and status bars)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dosText
        ]

        var row = 0
        for line in text.components(separatedBy: "\n") {
            let y = menuBarHeight + CGFloat(row) * cellSize.height
            if y + cellSize.height > bounds.height - statusBarHeight {
                break  // Don't draw beyond status bar
            }
            let attrString = NSAttributedString(string: line, attributes: attributes)
            attrString.draw(at: CGPoint(x: 5, y: y))
            row += 1
        }

        // Draw cursor (blinking block)
        if cursorVisible {
            let cursorX = 5 + CGFloat(cursorCol) * cellSize.width
            let cursorY = menuBarHeight + CGFloat(cursorRow) * cellSize.height

            dosText.setFill()
            let cursorRect = NSRect(x: cursorX, y: cursorY, width: cellSize.width, height: cellSize.height)
            cursorRect.fill()

            // Draw the character under the cursor in inverse video
            if Int(cursorRow) < text.components(separatedBy: "\n").count {
                let lines = text.components(separatedBy: "\n")
                let cursorLine = lines[Int(cursorRow)]
                if Int(cursorCol) < cursorLine.count {
                    let charIndex = cursorLine.index(cursorLine.startIndex, offsetBy: Int(cursorCol))
                    let char = String(cursorLine[charIndex])
                    let inverseAttrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: dosBlue  // Text color on cursor
                    ]
                    let charStr = NSAttributedString(string: char, attributes: inverseAttrs)
                    charStr.draw(at: CGPoint(x: cursorX, y: cursorY))
                }
            }
        }
    }

    func drawDropdownMenu(at menuIndex: Int) {
        let menu = menuItems[menuIndex]
        let menuRect = menuRects[menuIndex]

        // Calculate dropdown dimensions
        let maxWidth = menu.items.map { $0.count * 9 + 20 }.max() ?? 100
        let dropdownHeight = CGFloat(menu.items.count) * cellSize.height + 4
        let dropdownRect = NSRect(
            x: menuRect.minX,
            y: menuBarHeight,
            width: CGFloat(maxWidth),
            height: dropdownHeight
        )

        // Draw dropdown background (light gray)
        NSColor(white: 0.85, alpha: 1).setFill()
        dropdownRect.fill()

        // Draw dropdown border (black)
        NSColor.black.setStroke()
        let borderPath = NSBezierPath(rect: dropdownRect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // Draw menu items
        let itemAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        var itemY = menuBarHeight + 2
        for item in menu.items {
            if item == "---" {
                // Draw separator
                NSColor.darkGray.setStroke()
                let separatorPath = NSBezierPath()
                separatorPath.move(to: CGPoint(x: dropdownRect.minX + 2, y: itemY + cellSize.height / 2))
                separatorPath.line(to: CGPoint(x: dropdownRect.maxX - 2, y: itemY + cellSize.height / 2))
                separatorPath.lineWidth = 1
                separatorPath.stroke()
            } else {
                let itemStr = NSAttributedString(string: " " + item, attributes: itemAttrs)
                itemStr.draw(at: CGPoint(x: dropdownRect.minX, y: itemY))
            }
            itemY += cellSize.height
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let state = editState else { return }

        // Get key code and modifiers
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        // Convert NSEvent modifiers to Edit's modifier format
        var editModifiers: UInt32 = 0
        if modifiers.contains(.shift) {
            editModifiers |= 0x01
        }
        if modifiers.contains(.control) {
            editModifiers |= 0x02
        }
        if modifiers.contains(.option) {
            editModifiers |= 0x04
        }
        if modifiers.contains(.command) {
            editModifiers |= 0x08
        }

        // Send to Edit
        edit_handle_key(state, keyCode, editModifiers)

        // Reset cursor visibility on keypress
        cursorVisible = true

        // Mark for redraw (async is fine now that we fixed the flip() issue)
        setNeedsDisplay(bounds)
    }

    override func mouseDown(with event: NSEvent) {
        guard let state = editState else { return }

        // Get mouse location in view coordinates
        let location = convert(event.locationInWindow, from: nil)

        // Check if click is in menu bar
        if location.y < menuBarHeight {
            handleMenuClick(at: location)
            return
        }

        // Check if click is in dropdown menu
        if let menuIndex = activeMenu {
            if handleDropdownClick(at: location, menuIndex: menuIndex) {
                return
            }
        }

        // Click outside menu - close any open menu
        if activeMenu != nil {
            activeMenu = nil
            setNeedsDisplay(bounds)
            return
        }

        // Check if click is in the text area (between menu and status bars)
        guard location.y >= menuBarHeight && location.y < bounds.height - statusBarHeight else {
            return
        }

        // Convert to text coordinates
        let textY = location.y - menuBarHeight
        let row = Int32(textY / cellSize.height)
        let col = Int32(max(0, location.x - 5) / cellSize.width)

        // Set cursor position
        edit_set_cursor_pos(state, row, col)

        // Reset cursor visibility on click
        cursorVisible = true

        // Mark for redraw
        setNeedsDisplay(bounds)
    }

    func handleMenuClick(at location: CGPoint) {
        // Find which menu was clicked
        for (index, rect) in menuRects.enumerated() {
            if rect.contains(location) {
                if activeMenu == index {
                    // Clicked on already-open menu - close it
                    activeMenu = nil
                } else {
                    // Open this menu
                    activeMenu = index
                }
                setNeedsDisplay(bounds)
                return
            }
        }
    }

    func handleDropdownClick(at location: CGPoint, menuIndex: Int) -> Bool {
        let menu = menuItems[menuIndex]
        let menuRect = menuRects[menuIndex]

        // Calculate dropdown rect
        let maxWidth = menu.items.map { $0.count * 9 + 20 }.max() ?? 100
        let dropdownHeight = CGFloat(menu.items.count) * cellSize.height + 4
        let dropdownRect = NSRect(
            x: menuRect.minX,
            y: menuBarHeight,
            width: CGFloat(maxWidth),
            height: dropdownHeight
        )

        // Check if click is inside dropdown
        if dropdownRect.contains(location) {
            // Calculate which item was clicked
            let relativeY = location.y - menuBarHeight - 2
            let itemIndex = Int(relativeY / cellSize.height)

            if itemIndex >= 0 && itemIndex < menu.items.count {
                let item = menu.items[itemIndex]
                executeMenuAction(menu: menu.title, item: item)
                activeMenu = nil
                setNeedsDisplay(bounds)
            }
            return true
        }

        return false
    }

    func executeMenuAction(menu: String, item: String) {
        print("Menu action: \(menu) -> \(item)")

        switch (menu, item) {
        case ("File", "Exit"):
            NSApplication.shared.terminate(nil)

        case ("File", "New"):
            // Clear the document (implement later)
            print("New document")

        case ("Help", "About..."):
            showAboutDialog()

        default:
            print("Menu action not implemented: \(menu) -> \(item)")
        }
    }

    func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "Edit for macOS"
        alert.informativeText = "A native macOS implementation of MS-DOS Edit\n\nBuilt with Swift and Rust"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - File Monitoring

    func startFileMonitoring(path: String) {
        // Stop any existing monitoring
        stopFileMonitoring()

        // Open file descriptor for monitoring
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open file descriptor for monitoring: \(path)")
            return
        }

        // Create dispatch source for file system events
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            self?.handleFileChange(path: path)
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source.resume()
        fileMonitor = source
    }

    func stopFileMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    func handleFileChange(path: String) {
        let alert = NSAlert()
        alert.messageText = "File Changed"
        alert.informativeText = "The file \"\((path as NSString).lastPathComponent)\" has been modified by another application. Do you want to reload it?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Keep Current")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Reload the file
            openFile(path: path)
        }
    }

    // MARK: - Drag & Drop Support

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Check if we have a file URL
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let url = urls.first else {
            return false
        }

        // Open the dropped file
        openFile(path: url.path)
        return true
    }
}

// FFI declarations
@_silgen_name("edit_handle_key")
func edit_handle_key(_ state: OpaquePointer, _ key: UInt16, _ modifiers: UInt32)

@_silgen_name("edit_init")
func edit_init(_ width: Int32, _ height: Int32) -> OpaquePointer?

@_silgen_name("edit_destroy")
func edit_destroy(_ state: OpaquePointer)

@_silgen_name("edit_get_render_data")
func edit_get_render_data(_ state: OpaquePointer) -> OpaquePointer?

@_silgen_name("edit_free_render_data")
func edit_free_render_data(_ data: OpaquePointer?)

@_silgen_name("edit_render_data_cell_count")
func edit_render_data_cell_count(_ data: OpaquePointer?) -> Int32

@_silgen_name("edit_render_data_get_cell")
func edit_render_data_get_cell(_ data: OpaquePointer?, _ index: Int32) -> UnsafePointer<FramebufferCell>?

@_silgen_name("edit_update_text_cache")
func edit_update_text_cache(_ state: OpaquePointer)

@_silgen_name("edit_get_text_content")
func edit_get_text_content(_ state: OpaquePointer) -> UnsafePointer<UInt8>?

@_silgen_name("edit_get_text_length")
func edit_get_text_length(_ state: OpaquePointer) -> Int32

@_silgen_name("edit_get_cursor_pos")
func edit_get_cursor_pos(_ state: OpaquePointer, _ row: UnsafeMutablePointer<Int32>, _ col: UnsafeMutablePointer<Int32>)

@_silgen_name("edit_set_cursor_pos")
func edit_set_cursor_pos(_ state: OpaquePointer, _ row: Int32, _ col: Int32)

@_silgen_name("edit_new_file")
func edit_new_file(_ state: OpaquePointer)

@_silgen_name("edit_open_file")
func edit_open_file(_ state: OpaquePointer, _ path: UnsafePointer<CChar>)

@_silgen_name("edit_save_file_as")
func edit_save_file_as(_ state: OpaquePointer, _ path: UnsafePointer<CChar>)

struct MenuItem {
    let title: String
    let items: [String]
}

struct FramebufferCell {
    let ch: UInt32          // Rust char (4 bytes, UTF-32)
    let fg: UInt32          // StraightRgba (4 bytes)
    let bg: UInt32          // StraightRgba (4 bytes)
    let attrs: UInt8        // Attributes (1 byte)
    let _padding1: UInt8    // padding
    let _padding2: UInt8    // padding
    let _padding3: UInt8    // padding
    let x: Int              // CoordType/isize (8 bytes)
    let y: Int              // CoordType/isize (8 bytes)
}
