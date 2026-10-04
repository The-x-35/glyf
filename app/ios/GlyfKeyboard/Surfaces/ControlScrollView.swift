import UIKit

/// A scroll view whose content is buttons: tiles, cards, chips, strip icons.
///
/// UIScrollView refuses to take a touch away from a UIControl once it has
/// started, so a swipe that begins on a tile never scrolls; in a grid made of
/// tiles that means it never scrolls at all. Here a finger that starts
/// moving always becomes a scroll, and a tap is still a tap.
final class ControlScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        noEdgeEffects()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        noEdgeEffects()
    }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

extension UIScrollView {
    /// iOS 26 frosts a scroll view's edges where floating system UI sits over
    /// it (the scroll edge effect). Nothing of ours floats over a keyboard's
    /// lists, but iOS's own paste prompt does, and on a tester's iPhone 17 the
    /// strip's tools stayed frosted after it went away: a blurred panel over
    /// exactly the tools' scroll view, the g key beside it sharp (2026-10-04).
    /// Every scroll view in the keyboard turns them off.
    func noEdgeEffects() {
        if #available(iOS 26.0, *) {
            for effect in [topEdgeEffect, leftEdgeEffect, bottomEdgeEffect, rightEdgeEffect] {
                effect.isHidden = true
            }
        }
    }
}
