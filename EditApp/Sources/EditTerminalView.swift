import AppKit
import SwiftTerm

/// LocalProcessTerminalView subclass whose sole job is hiding SwiftTerm's
/// built-in NSScroller. MS Edit is a full-screen TUI with no scrollback content,
/// so the indicator is always wrong/empty and renders as a visual artifact.
///
/// Scroll wheel and Shift+click behaviours are handled via NSEvent local
/// monitors in TerminalViewController (SwiftTerm marks those NSView methods
/// as `public`, not `open`, so they cannot be overridden from outside the module).
class EditTerminalView: LocalProcessTerminalView {

    override func layout() {
        super.layout()
        // SwiftTerm repositions its NSScroller on every layout pass — re-hide it.
        subviews.forEach { if $0 is NSScroller { $0.isHidden = true } }
    }
}
