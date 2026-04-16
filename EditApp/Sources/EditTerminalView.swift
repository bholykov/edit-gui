import AppKit
import SwiftTerm

/// LocalProcessTerminalView subclass whose sole job is hiding SwiftTerm's
/// built-in NSScroller. MS Edit is a full-screen TUI with no scrollback content,
/// so the indicator is always wrong/empty and renders as a visual artifact.
///
/// Scroll wheel, double-click word selection, and Shift+drag selection are
/// handled via NSEvent local monitors in TerminalViewController (SwiftTerm marks
/// those NSView methods as `public`, not `open`, so they cannot be overridden
/// from outside the module).
class EditTerminalView: LocalProcessTerminalView {

    /// Hide NSScroller subviews immediately when they are inserted.
    /// SwiftTerm calls addSubview(_:) in setupScroller(); catching it here means
    /// the scroller is hidden from the first frame with no flash.
    override func addSubview(_ view: NSView) {
        super.addSubview(view)
        if view is NSScroller { view.isHidden = true }
    }

    override func layout() {
        super.layout()
        // SwiftTerm's NSScroller is repositioned (via autoresizingMask) on every
        // layout pass. Re-hide it here. Note: do NOT zero the frame — changing a
        // subview's frame inside layout() triggers setNeedsLayout on the parent,
        // causing an infinite loop and blocking the main thread (breaks keyboard).
        // isHidden is sufficient because updateScroller() never resets it.
        hideScrollers(in: self)
    }

    private func hideScrollers(in view: NSView) {
        for sub in view.subviews {
            if sub is NSScroller {
                sub.isHidden = true
            } else {
                hideScrollers(in: sub)
            }
        }
    }
}
