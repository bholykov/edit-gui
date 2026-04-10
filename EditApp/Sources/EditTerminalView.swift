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

    override func layout() {
        super.layout()
        // SwiftTerm's NSScroller is repositioned (via autoresizingMask) on every
        // layout pass. Hide it AND zero its frame so it takes no space.
        hideScrollers(in: self)
    }

    private func hideScrollers(in view: NSView) {
        for sub in view.subviews {
            if sub is NSScroller {
                sub.isHidden = true
                sub.frame = .zero
            } else {
                hideScrollers(in: sub)
            }
        }
    }
}
