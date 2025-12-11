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
    private let statusBarHeight: CGFloat = 20

    // Cursor state
    private var cursorVisible = true
    private var cursorBlinkTimer: Timer?

    // File management
    private var currentFilePath: String?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    // Selection state
    private var isSelecting = false
    private var selectionStartRow: Int32 = 0
    private var selectionStartCol: Int32 = 0

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

    // MARK: - Edit Operations

    func cutSelection() {
        guard let state = editState else { return }
        edit_cut(state)
        setNeedsDisplay(bounds)
    }

    func copySelection() {
        guard let state = editState else { return }
        edit_copy(state)
    }

    func pasteSelection() {
        guard let state = editState else { return }
        edit_paste(state)
        setNeedsDisplay(bounds)
    }

    func clearSelection() {
        guard let state = editState else { return }
        edit_delete_selection(state)
        setNeedsDisplay(bounds)
    }

    func selectAllText() {
        guard let state = editState else { return }
        edit_select_all(state)
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let state = editState else { return }

        // Fill with DOS blue background
        dosBlue.setFill()
        bounds.fill()

        // Get cursor position
        var cursorRow: Int32 = 0
        var cursorCol: Int32 = 0
        edit_get_cursor_pos(state, &cursorRow, &cursorCol)

        // Draw status bar at bottom with real cursor position
        dosMenuBg.setFill()
        NSRect(x: 0, y: bounds.height - statusBarHeight, width: bounds.width, height: statusBarHeight).fill()

        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dosMenuText
        ]
        let statusText = String(format: " Line %d   Col %d   F1=Help", cursorRow + 1, cursorCol + 1)
        let statusStr = NSAttributedString(string: statusText, attributes: statusAttrs)
        statusStr.draw(at: CGPoint(x: 5, y: bounds.height - statusBarHeight + 2))

        // Get text content from Edit
        edit_update_text_cache(state)
        let textLen = edit_get_text_length(state)
        guard textLen > 0 else { return }
        guard let textPtr = edit_get_text_content(state) else { return }

        let textData = Data(bytes: textPtr, count: Int(textLen))
        guard let text = String(data: textData, encoding: .utf8) else { return }

        // Get selection range if any
        var selectionStartOffset: Int = 0
        var selectionEndOffset: Int = 0
        let hasSelection = edit_get_selection_offsets(state, &selectionStartOffset, &selectionEndOffset)

        // Draw text line by line (full view, just avoiding status bar)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dosText
        ]

        // Selection highlight color (light blue)
        let selectionBg = NSColor(red: 0, green: 0.4, blue: 0.8, alpha: 0.5)

        var row = 0
        var byteOffset = 0
        for line in text.components(separatedBy: "\n") {
            let y = CGFloat(row) * cellSize.height
            if y + cellSize.height > bounds.height - statusBarHeight {
                break  // Don't draw beyond status bar
            }

            // Calculate byte offsets for this line
            let lineBytes = line.utf8.count
            let lineStartOffset = byteOffset
            let lineEndOffset = byteOffset + lineBytes

            // Draw selection highlight if this line overlaps with selection
            if hasSelection && selectionStartOffset < lineEndOffset && selectionEndOffset > lineStartOffset {
                // Calculate which columns in this line are selected
                let selStart = max(0, selectionStartOffset - lineStartOffset)
                let selEnd = min(lineBytes, selectionEndOffset - lineStartOffset)

                // Convert byte offsets to character positions (approximate for monospace)
                let startCol = line.utf8.prefix(selStart).count
                let endCol = line.utf8.prefix(selEnd).count

                let highlightX = 5 + CGFloat(startCol) * cellSize.width
                let highlightWidth = CGFloat(endCol - startCol) * cellSize.width

                selectionBg.setFill()
                NSRect(x: highlightX, y: y, width: highlightWidth, height: cellSize.height).fill()
            }

            // Draw the text
            let attrString = NSAttributedString(string: line, attributes: attributes)
            attrString.draw(at: CGPoint(x: 5, y: y))

            byteOffset = lineEndOffset + 1  // +1 for the newline character
            row += 1
        }

        // Draw cursor (blinking block)
        if cursorVisible {
            let cursorX = 5 + CGFloat(cursorCol) * cellSize.width
            let cursorY = CGFloat(cursorRow) * cellSize.height

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


    override func keyDown(with event: NSEvent) {
        guard let state = editState else { return }

        // Get key code and modifiers
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        // Let Cmd+shortcuts be handled by menu items
        if modifiers.contains(.command) {
            // Pass through to responder chain (menu items will handle)
            super.keyDown(with: event)
            return
        }

        // Handle Shift+Arrow keys for selection
        let isArrowKey = (keyCode >= 123 && keyCode <= 126) // Left, Right, Down, Up
        if modifiers.contains(.shift) && isArrowKey {
            // Start selection if not already selecting
            if !isSelecting {
                edit_selection_start(state)
                isSelecting = true

                // Get current cursor position as selection start
                edit_get_cursor_pos(state, &selectionStartRow, &selectionStartCol)
            }
        } else if isSelecting && !modifiers.contains(.shift) {
            // Clear selection if Shift is released
            edit_selection_clear(state)
            isSelecting = false
        }

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

        // Send to Edit
        edit_handle_key(state, keyCode, editModifiers)

        // If we're selecting, extend selection to new cursor position
        if isSelecting {
            var newRow: Int32 = 0
            var newCol: Int32 = 0
            edit_get_cursor_pos(state, &newRow, &newCol)
            edit_selection_extend(state, newRow, newCol)
        }

        // Reset cursor visibility on keypress
        cursorVisible = true

        // Mark for redraw
        setNeedsDisplay(bounds)
    }

    override func mouseDown(with event: NSEvent) {
        guard let state = editState else { return }

        // Get mouse location in view coordinates
        let location = convert(event.locationInWindow, from: nil)

        // Check if click is in the text area (above status bar)
        guard location.y < bounds.height - statusBarHeight else {
            return
        }

        // Convert to text coordinates
        let row = Int32(location.y / cellSize.height)
        let col = Int32(max(0, location.x - 5) / cellSize.width)

        // Clear any existing selection
        edit_selection_clear(state)
        isSelecting = false

        // Set cursor position
        edit_set_cursor_pos(state, row, col)

        // Start selection for potential drag
        edit_selection_start(state)
        isSelecting = true
        selectionStartRow = row
        selectionStartCol = col

        // Reset cursor visibility on click
        cursorVisible = true

        // Mark for redraw
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state = editState else { return }
        guard isSelecting else { return }

        // Get mouse location in view coordinates
        let location = convert(event.locationInWindow, from: nil)

        // Check if drag is in the text area
        guard location.y < bounds.height - statusBarHeight else {
            return
        }

        // Convert to text coordinates
        let row = Int32(location.y / cellSize.height)
        let col = Int32(max(0, location.x - 5) / cellSize.width)

        // Extend selection to new position
        edit_set_cursor_pos(state, row, col)
        edit_selection_extend(state, row, col)

        // Reset cursor visibility
        cursorVisible = true

        // Mark for redraw
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        // Keep selection active even after mouse up
        // Don't stop selecting - let user continue with keyboard
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

@_silgen_name("edit_select_all")
func edit_select_all(_ state: OpaquePointer)

@_silgen_name("edit_selection_start")
func edit_selection_start(_ state: OpaquePointer)

@_silgen_name("edit_selection_extend")
func edit_selection_extend(_ state: OpaquePointer, _ row: Int32, _ col: Int32)

@_silgen_name("edit_selection_clear")
func edit_selection_clear(_ state: OpaquePointer)

@_silgen_name("edit_has_selection")
func edit_has_selection(_ state: OpaquePointer) -> Bool

@_silgen_name("edit_get_selection_offsets")
func edit_get_selection_offsets(_ state: OpaquePointer, _ startOffset: UnsafeMutablePointer<Int>, _ endOffset: UnsafeMutablePointer<Int>) -> Bool

@_silgen_name("edit_copy")
func edit_copy(_ state: OpaquePointer)

@_silgen_name("edit_cut")
func edit_cut(_ state: OpaquePointer)

@_silgen_name("edit_paste")
func edit_paste(_ state: OpaquePointer)

@_silgen_name("edit_delete_selection")
func edit_delete_selection(_ state: OpaquePointer)

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
