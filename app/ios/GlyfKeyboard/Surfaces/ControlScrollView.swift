import UIKit

/// A scroll view whose content is buttons: tiles, cards, chips, strip icons.
///
/// UIScrollView refuses to take a touch away from a UIControl once it has
/// started, so a swipe that begins on a tile never scrolls; in a grid made of
/// tiles that means it never scrolls at all. Here a finger that starts
/// moving always becomes a scroll, and a tap is still a tap.
final class ControlScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}
