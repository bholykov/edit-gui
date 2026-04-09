import AppKit
import SwiftTerm

/// LocalProcessTerminalView subclass that fixes three issues specific to
/// hosting MS Edit (a full-screen TUI) inside SwiftTerm:
///
/// 1. **Scrollbar**: SwiftTerm renders a private NSScroller for its scrollback
///    buffer. MS Edit produces no scrollback content (it redraws the screen via
///    cursor-positioning sequences), so the indicator is always wrong. Hidden
///    by overriding layout() so it stays gone even after SwiftTerm repositions it.
///
/// 2. **Scroll wheel**: SwiftTerm's scrollWheel always routes delta to the
///    scrollback buffer, never the PTY. We bypass that and send Up/Down arrow
///    escape sequences directly to the MS Edit process instead.
///
/// 3. **Text selection**: MS Edit enables ?1002 cell-motion mouse reporting,
///    which causes SwiftTerm to forward all clicks to the PTY (bypassing its own
///    selection logic). Holding Shift temporarily disables mouse reporting so
///    SwiftTerm can perform its native selection on click+drag.
class EditTerminalView: LocalProcessTerminalView {

    // MARK: - Scrollbar

    override func layout() {
        super.layout()
        // Keep SwiftTerm's NSScroller hidden — it is repositioned on every layout.
        subviews.forEach { if $0 is NSScroller { $0.isHidden = true } }
    }

    // MARK: - Scroll wheel → PTY arrows

    override func scrollWheel(with event: NSEvent) {
        guard event.deltaY != 0 else { return }
        // Scale: one scroll notch ≈ deltaY 3–5; send proportional arrow presses.
        let lines = max(1, Int(abs(event.deltaY).rounded()))
        // Respect application-cursor mode (\eOA/B) vs normal mode (\e[A/B).
        let seq = event.deltaY > 0
            ? (terminal.applicationCursor ? "\u{1b}OA" : "\u{1b}[A")  // Up
            : (terminal.applicationCursor ? "\u{1b}OB" : "\u{1b}[B")  // Down
        for _ in 0..<lines { send(txt: seq) }
    }

    // MARK: - Shift+click selection bypass

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            // Temporarily disable mouse reporting so SwiftTerm handles selection
            // rather than forwarding the click to the MS Edit PTY.
            let saved = allowMouseReporting
            allowMouseReporting = false
            super.mouseDown(with: event)
            allowMouseReporting = saved
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            let saved = allowMouseReporting
            allowMouseReporting = false
            super.mouseDragged(with: event)
            allowMouseReporting = saved
        } else {
            super.mouseDragged(with: event)
        }
    }
}
