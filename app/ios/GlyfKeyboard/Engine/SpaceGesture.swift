import CoreGraphics
import Foundation

/// The space bar carries three gestures on one key:
///
///  · tap                                  → a space
///  · glide at any point while holding     → the cursor follows the finger
///    (Gboard's straight swipe, Apple's press-pause-glide)
///  · hold still for `holdThreshold`       → the AI launches right then,
///                                           finger still down
///
/// Nothing waits for the lift: a glide is recognised the moment the finger
/// travels, and the AI the moment the finger has stayed still long enough.
/// Once the AI has launched the gesture is spent — later movement is ignored.
///
/// Pure value type: the view feeds it touches and a timer tick, and performs
/// the returned effects. Unit-tested in RunnerTests.
struct SpaceGesture {

    enum Phase: Equatable {
        case pending   // down, charge ring filling
        case gliding   // cursor follows the finger
        case launched  // AI is up
        case finished
    }

    enum Effect: Equatable {
        case beginGlide          // keys go blank (trackpad look) + haptic
        case moveCursor(Int)     // grapheme clusters; negative = left
        case endGlide
        case openBar             // ripple + AI, finger still down
        case typeSpace
    }

    /// Still this long with no glide → the AI launches. The platform
    /// long-press length (UILongPressGestureRecognizer's default): enough
    /// for Apple's press-pause-glide, short enough to feel like a hold.
    /// The space key's charge ring fills over exactly this time.
    static let holdThreshold: TimeInterval = 0.5
    /// Travel that means "glide", not a resting thumb.
    static let swipeSlop: CGFloat = 10
    /// Finger travel per character at a slow, precise pace.
    static let pointsPerCharacter: CGFloat = 9
    /// Fast flicks cover long distances: gain ramps from 1× at 250pt/s to
    /// 2.6× at 1050pt/s. Slow drags stay character-exact.
    static func gain(forSpeed speed: CGFloat) -> CGFloat {
        1 + min(max((speed - 250) / 500, 0), 1.6)
    }

    private(set) var phase: Phase = .pending
    private let startX: CGFloat
    private let startTime: TimeInterval
    private var lastX: CGFloat
    private var lastTime: TimeInterval
    private var accumulated: CGFloat = 0

    init(x: CGFloat, y: CGFloat, time: TimeInterval) {
        startX = x
        startTime = time
        lastX = x
        lastTime = time
    }

    /// Not yet gliding and not yet held long enough, by the touch clock —
    /// the only state in which sliding off the bar cancels the key.
    func isUndecided(at time: TimeInterval) -> Bool {
        phase == .pending && time - startTime < Self.holdThreshold
    }

    /// The hold timer fired with the finger still down and unmoved.
    mutating func holdElapsed() -> [Effect] {
        guard phase == .pending else { return [] }
        phase = .launched
        return [.openBar]
    }

    /// Decisions follow the touches' own timestamps, not the timer alone: on
    /// a busy main thread a move or the lift can be delivered before a late
    /// timer runs, and a real hold must still launch the AI.
    private mutating func catchUp(to time: TimeInterval) -> [Effect] {
        guard phase == .pending, time - startTime >= Self.holdThreshold else { return [] }
        return holdElapsed()
    }

    mutating func moved(x: CGFloat, y: CGFloat, time: TimeInterval) -> [Effect] {
        let launch = catchUp(to: time)
        switch phase {
        case .pending:
            guard abs(x - startX) > Self.swipeSlop else { return [] }
            phase = .gliding
            lastX = x
            lastTime = time
            accumulated = 0
            return [.beginGlide]
        case .gliding:
            let dx = x - lastX
            let dt = max(time - lastTime, 0.001)
            let speed = abs(dx) / CGFloat(dt)
            lastX = x
            lastTime = time
            accumulated += dx * Self.gain(forSpeed: speed)
            let steps = Int(accumulated / Self.pointsPerCharacter)
            guard steps != 0 else { return [] }
            accumulated -= CGFloat(steps) * Self.pointsPerCharacter
            return [.moveCursor(steps)]
        case .launched, .finished:
            return launch
        }
    }

    mutating func ended(time: TimeInterval) -> [Effect] {
        let launch = catchUp(to: time)
        defer { phase = .finished }
        switch phase {
        case .pending: return [.typeSpace]
        case .gliding: return [.endGlide]
        case .launched: return launch
        case .finished: return []
        }
    }

    mutating func cancelled() -> [Effect] {
        defer { phase = .finished }
        return phase == .gliding ? [.endGlide] : []
    }
}

/// A local mirror of the text around the cursor, so a glide moves by what
/// the user SEES. `adjustTextPosition(byCharacterOffset:)` counts UTF-16
/// code units, so stepping by 1 walks into the middle of 👍🏽 (4 units), a
/// flag (4) or a decomposed é (2) and the host either clamps or splits it.
/// The mirror steps whole grapheme clusters and reports the UTF-16 distance.
///
/// The proxy's context is truncated and refreshes asynchronously after a
/// move, so the mirror is taken once when the glide starts and updated
/// locally. When it runs out (the host holds more text than the proxy
/// exposed) it falls back to single code units and marks itself stale so
/// the caller re-reads the proxy.
struct CursorMirror {
    private(set) var before: String
    private(set) var after: String
    private(set) var isStale = false

    init(before: String, after: String) {
        self.before = before
        self.after = after
    }

    /// UTF-16 offset for `adjustTextPosition` that moves `graphemes`
    /// clusters (negative = left).
    mutating func offset(forGraphemes graphemes: Int) -> Int {
        var units = 0
        if graphemes < 0 {
            for _ in 0..<(-graphemes) {
                guard let last = before.last else {
                    isStale = true
                    units -= 1
                    continue
                }
                before.removeLast()
                after.insert(last, at: after.startIndex)
                units -= String(last).utf16.count
            }
        } else {
            for _ in 0..<graphemes {
                guard let first = after.first else {
                    isStale = true
                    units += 1
                    continue
                }
                after.removeFirst()
                before.append(first)
                units += String(first).utf16.count
            }
        }
        return units
    }
}
