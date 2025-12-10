//! FFI bridge for Swift/Cocoa macOS app.
//!
//! This module exposes C-compatible functions that can be called from Swift.

use std::ffi::CStr;
use std::os::raw::c_char;
use std::ptr;
use std::sync::Once;

use crate::arena;
use crate::clipboard::Clipboard;
use crate::framebuffer::{Framebuffer, FramebufferCell};
use crate::helpers::{Point, Size, MEBI};
use crate::buffer::{RcTextBuffer, TextBuffer};
use crate::input::{InputKey, kbmod, vk};

static INIT: Once = Once::new();

/// Maps macOS key codes to Edit virtual keys
fn macos_keycode_to_vk(keycode: u16) -> Option<InputKey> {
    match keycode {
        // Letters (macOS uses ANSI layout key codes)
        0 => Some(vk::A),
        11 => Some(vk::B),
        8 => Some(vk::C),
        2 => Some(vk::D),
        14 => Some(vk::E),
        3 => Some(vk::F),
        5 => Some(vk::G),
        4 => Some(vk::H),
        34 => Some(vk::I),
        38 => Some(vk::J),
        40 => Some(vk::K),
        37 => Some(vk::L),
        46 => Some(vk::M),
        45 => Some(vk::N),
        31 => Some(vk::O),
        35 => Some(vk::P),
        12 => Some(vk::Q),
        15 => Some(vk::R),
        1 => Some(vk::S),
        17 => Some(vk::T),
        32 => Some(vk::U),
        9 => Some(vk::V),
        13 => Some(vk::W),
        7 => Some(vk::X),
        16 => Some(vk::Y),
        6 => Some(vk::Z),

        // Numbers
        29 => Some(vk::N0),
        18 => Some(vk::N1),
        19 => Some(vk::N2),
        20 => Some(vk::N3),
        21 => Some(vk::N4),
        23 => Some(vk::N5),
        22 => Some(vk::N6),
        26 => Some(vk::N7),
        28 => Some(vk::N8),
        25 => Some(vk::N9),

        // Special keys
        36 => Some(vk::RETURN),
        48 => Some(vk::TAB),
        49 => Some(vk::SPACE),
        51 => Some(vk::BACK),
        53 => Some(vk::ESCAPE),

        // Arrow keys
        123 => Some(vk::LEFT),
        124 => Some(vk::RIGHT),
        125 => Some(vk::DOWN),
        126 => Some(vk::UP),

        // Home/End
        115 => Some(vk::HOME),
        119 => Some(vk::END),
        116 => Some(vk::PRIOR),  // Page Up
        121 => Some(vk::NEXT),   // Page Down

        // Delete/Insert
        117 => Some(vk::DELETE),
        114 => Some(vk::INSERT),

        // Function keys
        122 => Some(vk::F1),
        120 => Some(vk::F2),
        99 => Some(vk::F3),
        118 => Some(vk::F4),
        96 => Some(vk::F5),
        97 => Some(vk::F6),
        98 => Some(vk::F7),
        100 => Some(vk::F8),
        101 => Some(vk::F9),
        109 => Some(vk::F10),
        103 => Some(vk::F11),
        111 => Some(vk::F12),

        _ => None,
    }
}

/// Opaque handle to Edit state
pub struct EditState {
    framebuffer: Framebuffer,
    window_size: Size,
    // Active document buffer
    document: Option<RcTextBuffer>,
    // Cached text content for FFI (owned)
    cached_text: Vec<u8>,
    // Clipboard for cut/copy/paste
    clipboard: Clipboard,
}

/// Opaque handle to render data
pub struct RenderData {
    cells: Vec<FramebufferCell>,
    width: i32,
    height: i32,
}

/// Initializes Edit with the given window size.
/// Returns an opaque pointer to the Edit state.
#[unsafe(no_mangle)]
pub extern "C" fn edit_init(width: i32, height: i32) -> *mut EditState {
    // Initialize arena allocator once
    INIT.call_once(|| {
        if let Err(e) = arena::init(512 * MEBI) {
            eprintln!("    ✗ Failed to initialize arena: {:?}", e);
        } else {
            eprintln!("    ✓ Arena initialized");
        }
    });

    let window_size = Size {
        width: width as isize,
        height: height as isize,
    };

    eprintln!("    → Creating framebuffer...");
    let mut framebuffer = Framebuffer::new();
    framebuffer.flip(window_size);
    eprintln!("    ✓ Framebuffer created");

    // Add some test content
    use crate::framebuffer::IndexedColor;
    use crate::helpers::Rect;

    // Draw test text
    framebuffer.replace_text(0, 0, window_size.width, "Edit for macOS - Native GUI");
    framebuffer.replace_text(2, 0, window_size.width, "Hello from Rust + Swift!");
    framebuffer.replace_text(3, 0, window_size.width, "This is MS Edit running in a native macOS window.");

    // Add some colors
    framebuffer.blend_bg(
        Rect { left: 0, top: 0, right: 28, bottom: 1 },
        framebuffer.indexed(IndexedColor::Blue)
    );
    framebuffer.blend_fg(
        Rect { left: 0, top: 0, right: 28, bottom: 1 },
        framebuffer.indexed(IndexedColor::BrightWhite)
    );

    // Create a new document with some initial content
    eprintln!("    → Creating TextBuffer...");
    let document = match TextBuffer::new_rc(true) {
        Ok(buf) => {
            eprintln!("    ✓ TextBuffer created");
            eprintln!("    → Writing initial content...");
            let mut tb = buf.borrow_mut();
            tb.write_raw(b"Welcome to Edit for macOS!\n\nThis is a native macOS window running MS Edit.\n\nTry typing...");
            drop(tb);
            eprintln!("    ✓ Initial content written");
            buf
        },
        Err(e) => {
            eprintln!("    ✗ Failed to create TextBuffer: {:?}", e);
            return ptr::null_mut();
        }
    };

    let state = Box::new(EditState {
        framebuffer,
        window_size,
        document: Some(document),
        cached_text: Vec::new(),
        clipboard: Clipboard::default(),
    });

    eprintln!("    ✓ Edit state initialized successfully");

    Box::into_raw(state)
}

/// Destroys the Edit state.
#[unsafe(no_mangle)]
pub extern "C" fn edit_destroy(state: *mut EditState) {
    if !state.is_null() {
        unsafe {
            let _ = Box::from_raw(state);
        }
    }
}

/// Handles keyboard input.
#[unsafe(no_mangle)]
pub extern "C" fn edit_handle_key(state: *mut EditState, key: u16, modifiers: u32) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    // Convert macOS key code to InputKey
    let input_key = if let Some(vk) = macos_keycode_to_vk(key) {
        // Apply modifiers (macOS uses: 0x01=Shift, 0x02=Ctrl, 0x04=Alt, 0x08=Cmd)
        let mut mods = kbmod::NONE;
        if modifiers & 0x01 != 0 {
            mods |= kbmod::SHIFT;
        }
        if modifiers & 0x02 != 0 {
            mods |= kbmod::CTRL;
        }
        if modifiers & 0x04 != 0 {
            mods |= kbmod::ALT;
        }
        // Note: Ignoring Command (0x08) for now as Edit doesn't have a modifier for it

        vk | mods
    } else {
        // Unknown key
        return;
    };

    // Process the key through Edit's text buffer
    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();

        // Handle basic text input - for now just process printable characters
        // TODO: This is a simplified implementation. Edit's full TUI uses a more
        // sophisticated input processing system.

        // For now, just write letters/numbers
        let key_value = input_key.key().value();
        if key_value >= 'A' as u32 && key_value <= 'Z' as u32 {
            let ch = key_value as u8 as char;
            let text = if input_key.modifiers().contains(kbmod::SHIFT) {
                ch.to_string()
            } else {
                ch.to_lowercase().to_string()
            };
            buffer.write_canon(text.as_bytes());
        } else if key_value >= '0' as u32 && key_value <= '9' as u32 {
            let ch = key_value as u8 as char;
            buffer.write_canon(ch.to_string().as_bytes());
        } else if key_value == ' ' as u32 {
            buffer.write_canon(b" ");
        } else if key_value == '\r' as u32 {
            buffer.write_canon(b"\n");
        } else if key_value == 0x08 {  // Backspace
            buffer.delete(crate::buffer::CursorMovement::Grapheme, 1);
        }
    }

    // DON'T call flip() here - it clears everything! Only call on resize.
    // Clear the background by filling with black
    state.framebuffer.blend_bg(
        crate::helpers::Rect {
            left: 0,
            top: 0,
            right: state.window_size.width,
            bottom: state.window_size.height,
        },
        crate::oklab::StraightRgba::from_le(0xFF000000),
    );

    // Show key press feedback
    let key_info = format!("Last key: code={} mods=0x{:x} -> vk=0x{:x}", key, modifiers, input_key.value());
    state.framebuffer.replace_text(0, 0, state.window_size.width, &key_info);

    // Render document content
    if let Some(doc) = &state.document {
        let buffer = doc.borrow();
        let text_bytes = buffer.read_forward(0);

        // Convert bytes to string and split by lines
        if let Ok(text) = std::str::from_utf8(text_bytes) {
            let mut row = 2;
            for line in text.lines().take(30) {
                state.framebuffer.replace_text(row, 0, state.window_size.width, line);
                row += 1;
            }
        }
    }
}

/// Handles mouse input.
#[unsafe(no_mangle)]
pub extern "C" fn edit_handle_mouse(state: *mut EditState, x: i32, y: i32, button: i32) {
    if state.is_null() {
        return;
    }

    let _state = unsafe { &mut *state };

    // TODO: Convert to Edit's mouse coordinates and handle click
    let _ = (x, y, button);
}

/// Creates a new file.
#[unsafe(no_mangle)]
pub extern "C" fn edit_new_file(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    // Create a new empty document
    match TextBuffer::new_rc(true) {
        Ok(buf) => {
            state.document = Some(buf);
            eprintln!("✓ New file created");
        }
        Err(e) => {
            eprintln!("✗ Failed to create new file: {:?}", e);
        }
    }
}

/// Opens a file at the given path.
#[unsafe(no_mangle)]
pub extern "C" fn edit_open_file(state: *mut EditState, path: *const c_char) {
    if state.is_null() || path.is_null() {
        return;
    }

    let state = unsafe { &mut *state };
    let path_str = unsafe { CStr::from_ptr(path) }.to_string_lossy();

    eprintln!("Opening file: {}", path_str);

    // Create a new buffer and load the file
    match TextBuffer::new_rc(true) {
        Ok(buf) => {
            let mut tb = buf.borrow_mut();

            // Try to open and read the file
            match std::fs::File::open(path_str.as_ref()) {
                Ok(mut file) => {
                    match tb.read_file(&mut file, None) {
                        Ok(_) => {
                            drop(tb);
                            state.document = Some(buf);
                            eprintln!("✓ File loaded successfully");
                        }
                        Err(e) => {
                            eprintln!("✗ Failed to read file: {:?}", e);
                        }
                    }
                }
                Err(e) => {
                    eprintln!("✗ Failed to open file: {:?}", e);
                }
            }
        }
        Err(e) => {
            eprintln!("✗ Failed to create TextBuffer: {:?}", e);
        }
    }
}


/// Saves the current file to a new path.
#[unsafe(no_mangle)]
pub extern "C" fn edit_save_file_as(state: *mut EditState, path: *const c_char) {
    if state.is_null() || path.is_null() {
        return;
    }

    let state = unsafe { &mut *state };
    let path_str = unsafe { CStr::from_ptr(path) }.to_string_lossy();

    eprintln!("Saving file to: {}", path_str);

    if let Some(doc) = &state.document {
        let mut tb = doc.borrow_mut();

        match std::fs::File::create(path_str.as_ref()) {
            Ok(mut file) => {
                match tb.write_file(&mut file) {
                    Ok(_) => {
                        eprintln!("✓ File saved successfully");
                    }
                    Err(e) => {
                        eprintln!("✗ Failed to write file: {:?}", e);
                    }
                }
            }
            Err(e) => {
                eprintln!("✗ Failed to create file: {:?}", e);
            }
        }
    } else {
        eprintln!("✗ No document to save");
    }
}

/// Handles window resize.
#[unsafe(no_mangle)]
pub extern "C" fn edit_resize(state: *mut EditState, width: i32, height: i32) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    state.window_size = Size {
        width: width as isize,
        height: height as isize,
    };

    state.framebuffer.flip(state.window_size);
}

/// Updates the cached text content from the document buffer.
/// This must be called before accessing text content via FFI.
#[unsafe(no_mangle)]
pub extern "C" fn edit_update_text_cache(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let buffer = doc.borrow();
        let text_bytes = buffer.read_forward(0);
        state.cached_text = text_bytes.to_vec();
    } else {
        state.cached_text.clear();
    }
}

/// Gets the text content directly (fast path - skip framebuffer cells).
/// IMPORTANT: Call edit_update_text_cache() first to ensure fresh data.
#[unsafe(no_mangle)]
pub extern "C" fn edit_get_text_content(state: *mut EditState) -> *const u8 {
    if state.is_null() {
        return ptr::null();
    }

    let state = unsafe { &*state };

    if state.cached_text.is_empty() {
        ptr::null()
    } else {
        state.cached_text.as_ptr()
    }
}

/// Gets text content length.
/// IMPORTANT: Call edit_update_text_cache() first to ensure fresh data.
#[unsafe(no_mangle)]
pub extern "C" fn edit_get_text_length(state: *mut EditState) -> i32 {
    if state.is_null() {
        return 0;
    }

    let state = unsafe { &*state };
    state.cached_text.len() as i32
}

/// Gets the cursor position (visual position in rows and columns).
/// Returns a tuple (row, col) where both are 0-indexed.
#[unsafe(no_mangle)]
pub extern "C" fn edit_get_cursor_pos(state: *mut EditState, row: *mut i32, col: *mut i32) {
    if state.is_null() || row.is_null() || col.is_null() {
        return;
    }

    let state = unsafe { &*state };

    if let Some(doc) = &state.document {
        let buffer = doc.borrow();
        let pos = buffer.cursor_visual_pos();
        unsafe {
            *row = pos.y as i32;
            *col = pos.x as i32;
        }
    } else {
        unsafe {
            *row = 0;
            *col = 0;
        }
    }
}

/// Sets the cursor position (visual position in rows and columns).
/// Both row and col are 0-indexed.
#[unsafe(no_mangle)]
pub extern "C" fn edit_set_cursor_pos(state: *mut EditState, row: i32, col: i32) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        let pos = crate::helpers::Point {
            x: col as isize,
            y: row as isize,
        };
        buffer.cursor_move_to_visual(pos);
    }
}

/// Selects all text in the document.
#[unsafe(no_mangle)]
pub extern "C" fn edit_select_all(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        buffer.select_all();
    }
}

/// Starts a selection at the current cursor position.
/// This is called when the user begins a selection operation.
#[unsafe(no_mangle)]
pub extern "C" fn edit_selection_start(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        // Start selection by updating selection to current cursor position
        // This sets the "beg" anchor point
        let pos = buffer.cursor_visual_pos();
        buffer.selection_update_visual(pos);
    }
}

/// Extends the selection to the given cursor position.
/// This moves the cursor and updates the selection endpoint.
#[unsafe(no_mangle)]
pub extern "C" fn edit_selection_extend(state: *mut EditState, row: i32, col: i32) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        let pos = Point {
            x: col as isize,
            y: row as isize,
        };
        buffer.selection_update_visual(pos);
    }
}

/// Clears the current selection.
#[unsafe(no_mangle)]
pub extern "C" fn edit_selection_clear(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        buffer.clear_selection();
    }
}

/// Checks if there is an active selection.
#[unsafe(no_mangle)]
pub extern "C" fn edit_has_selection(state: *mut EditState) -> bool {
    if state.is_null() {
        return false;
    }

    let state = unsafe { &*state };

    if let Some(doc) = &state.document {
        let buffer = doc.borrow();
        buffer.has_selection()
    } else {
        false
    }
}

/// Copies selected text to clipboard.
#[unsafe(no_mangle)]
pub extern "C" fn edit_copy(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        buffer.copy(&mut state.clipboard);
    }
}

/// Cuts selected text to clipboard.
#[unsafe(no_mangle)]
pub extern "C" fn edit_cut(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        buffer.cut(&mut state.clipboard);
    }
}

/// Pastes text from clipboard.
#[unsafe(no_mangle)]
pub extern "C" fn edit_paste(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        buffer.paste(&state.clipboard);
    }
}

/// Deletes selected text.
#[unsafe(no_mangle)]
pub extern "C" fn edit_delete_selection(state: *mut EditState) {
    if state.is_null() {
        return;
    }

    let state = unsafe { &mut *state };

    if let Some(doc) = &state.document {
        let mut buffer = doc.borrow_mut();
        buffer.clear_selection();
    }
}

/// Gets render data (cells) for the current frame.
/// Returns an opaque pointer to RenderData.
#[unsafe(no_mangle)]
pub extern "C" fn edit_get_render_data(state: *mut EditState) -> *mut RenderData {
    if state.is_null() {
        return ptr::null_mut();
    }

    let state = unsafe { &*state };

    // Collect all cells from the framebuffer
    let cells: Vec<FramebufferCell> = state.framebuffer.cells().collect();

    let render_data = Box::new(RenderData {
        cells,
        width: state.window_size.width as i32,
        height: state.window_size.height as i32,
    });

    Box::into_raw(render_data)
}

/// Frees render data.
#[unsafe(no_mangle)]
pub extern "C" fn edit_free_render_data(data: *mut RenderData) {
    if !data.is_null() {
        unsafe {
            let _ = Box::from_raw(data);
        }
    }
}

/// Gets the number of cells in the render data.
#[unsafe(no_mangle)]
pub extern "C" fn edit_render_data_cell_count(data: *const RenderData) -> i32 {
    if data.is_null() {
        return 0;
    }

    let data = unsafe { &*data };
    data.cells.len() as i32
}

/// Gets a specific cell from the render data.
/// Returns null if index is out of bounds.
#[unsafe(no_mangle)]
pub extern "C" fn edit_render_data_get_cell(data: *const RenderData, index: i32) -> *const FramebufferCell {
    if data.is_null() {
        return ptr::null();
    }

    let data = unsafe { &*data };

    data.cells.get(index as usize)
        .map(|cell| cell as *const FramebufferCell)
        .unwrap_or(ptr::null())
}
