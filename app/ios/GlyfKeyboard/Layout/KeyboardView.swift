import UIKit

protocol KeyboardViewDelegate: AnyObject {
    func kbInsert(_ text: String)
    func kbDeleteBackward()
    func kbSpaceTapped()
    func kbReturnTapped()
    /// Return held: a line break in the message, never its send.
    func kbReturnHeld()
    func kbGlobe(event: UIEvent?, key: KeyView, longPress: Bool)
    func kbOpenEmoji()
    /// A space-bar glide started / moved / ended. Moves are in grapheme
    /// clusters (negative = left); the VC maps them to UTF-16 for the proxy.
    func kbCursorGlideBegan()
    func kbMoveCursor(graphemes: Int)
    func kbCursorGlideEnded()
    /// Space held still until the ring closed — the AI launches 60ms after
    /// ignition (§5.3), finger still down.
    func kbSpaceHoldIgnited(origin: KeyView)
    /// Whether the space bar's long gestures apply right now. While an
    /// in-keyboard editor owns the keys (bar prompt, search, note) there is
    /// no host cursor to glide and a hold is just a space; secure fields
    /// never open the bar (§11.9).
    func kbSpaceGestures() -> (glide: Bool, bar: Bool)
    /// A bound key held ≥320ms (M2 — Glyf Keys, §6.5).
    func kbBoundKeyIgnited(keyId: String, glyfId: String, origin: KeyView)
    /// Whether a held key may run what it is bound to right now.
    func kbBindingsLive() -> Bool
    func kbTextInteraction()
    /// Glide typing (Arpit, 2026-10-07: "implement glide typing, like glide
    /// over keyboard to type"): whether a glide may start now, the word to
    /// float over the finger as it moves, and the lift that types it.
    func kbGlideAllowed() -> Bool
    func kbGlideMoved(_ points: [GlidePoint], layout: GlideDecoder.Layout) -> String?
    func kbGlideEnded(_ points: [GlidePoint], layout: GlideDecoder.Layout)
}

/// The key grid. Owns ALL touch handling (multi-touch typing, accent slides,
/// space-bar cursor glide, delete repeat, hold arming) and the ripple driver.
/// Manual frame layout — no per-key autolayout, no per-key blur (§5.2).
final class KeyboardView: UIView, UIInputViewAudioFeedback {

    weak var delegate: KeyboardViewDelegate?

    private(set) var mode: KeyboardMode = .letters
    private(set) var shift: ShiftState = .on   // sentence start
    private var autoShifted = true
    private var keys: [KeyView] = []
    private var rows: [[KeySpec]] = []
    private var unitWidth: CGFloat = 34
    /// Distance between key centers across a row, and between rows — the
    /// typing engine's grid (FORMAT.md "Scoring").
    private var keyPitch: CGFloat = 40
    private var rowHeight: CGFloat = 54

    /// Where the last letter tap landed, relative to its key's center, in
    /// key widths. Nil for accent picks and anything not tapped on a key.
    private(set) var lastTapOffset: (Float, Float)?

    /// Row spacing in key widths, for the engine's key geometry.
    var rowPitch: Float {
        guard keyPitch > 0 else { return 1.44 }
        return Float(rowHeight / keyPitch)
    }

    var enableInputClicksWhenVisible: Bool { true }

    // MARK: Per-touch state

    private enum TouchMode { case pending, space, accentPopup, holdFired, slidAway, deleteRepeat, glide }

    private final class TouchState {
        let key: KeyView
        let start: CGPoint
        let startTime: TimeInterval
        var mode: TouchMode = .pending
        var holdTimer: Timer?
        var repeatTimer: Timer?
        var repeatCount = 0
        var space: SpaceGesture?
        /// False when the glide started over an in-keyboard editor.
        var glides = true
        var popup: AccentPopup?
        /// Glide typing: the finger's path in key widths, the key lit under
        /// it, and when the word over it was last worked out.
        var path: [GlidePoint] = []
        var lit: KeyView?
        var decodedAt: TimeInterval = 0
        init(key: KeyView, start: CGPoint, time: TimeInterval = 0) {
            self.key = key
            self.start = start
            startTime = time
        }
        func invalidate() {
            holdTimer?.invalidate()
            repeatTimer?.invalidate()
            popup?.removeFromSuperview()
        }
    }

    private var touchStates: [ObjectIdentifier: TouchState] = [:]

    /// The ribbon and floating word of a glide, above every key.
    private let trail = GlideTrail()
    /// The letters' centres in key widths, for the glide decoder; nil on a
    /// symbol layer or a digit pad, where there is no glide typing.
    private var glideLayout: GlideDecoder.Layout?
    /// Travel from where the finger landed that makes a touch a glide.
    static let glideStart: CGFloat = 0.7

    init() {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = Glass.touchableGrid
        addSubview(trail)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Build + layout

    var needsGlobe = false
    /// How the return key looks for the focused field: Apple's glyph or
    /// word, and blue for go, search, send and done.
    var returnFace = ReturnFace.plain {
        didSet { if returnFace != oldValue { rebuild() } }
    }
    /// False while a field that enables its return key automatically is
    /// empty: Apple draws the key greyed then.
    var returnEnabled = true {
        didSet {
            guard returnEnabled != oldValue else { return }
            for kv in keys { if case .ret = kv.spec.kind { kv.returnEnabled = returnEnabled } }
        }
    }
    /// The focused field's flavor — email/URL space rows, digit pads (§6.1).
    var context: KeyboardContext = .text {
        didSet { if context != oldValue { rebuild() } }
    }

    func rebuild() {
        backgroundColor = Glass.touchableGrid // appearance may have flipped
        keys.forEach { $0.removeFromSuperview() }
        keys = []
        let s = SettingsStore.current
        rows = KeyboardLayout.rows(mode: mode, numberRow: s.numberRow && mode == .letters,
                                   globe: needsGlobe, context: context)
        for row in rows {
            for spec in row {
                let kv = KeyView(spec: spec)
                kv.isUserInteractionEnabled = false // container drives touches
                if case .ret = spec.kind {
                    kv.returnFace = returnFace
                    kv.returnEnabled = returnEnabled
                }
                // A digit pad is Apple's pad: no bound keys on it.
                if let c = spec.char, !spec.pad { kv.isBound = s.bindings[c] != nil }
                kv.shifted = shiftActive
                kv.setShiftState(shift)
                addSubview(kv)
                keys.append(kv)
            }
        }
        bringSubviewToFront(trail)
        setNeedsLayout()
    }

    func refreshBindings() {
        let s = SettingsStore.current
        for kv in keys {
            if let c = kv.spec.char, !kv.spec.pad { kv.isBound = s.bindings[c] != nil }
        }
    }

    private var shiftActive: Bool { shift != .off }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !rows.isEmpty, bounds.width > 100 else { return }
        let s = SettingsStore.current
        // Every number here is measured off the system keyboard (KeyMetrics
        // and KeyboardLayout.frames), so the keys land where iOS puts them
        // on whatever phone this is.
        let grid = KeyboardLayout.frames(
            rows: rows, size: bounds.size, context: context,
            leftInset: s.oneHanded == "right" ? 56 : 0,
            rightInset: s.oneHanded == "left" ? 56 : 0)
        keyPitch = grid.pitch
        unitWidth = grid.unitWidth
        rowHeight = grid.rowHeight
        for (kv, frame) in zip(keys, grid.frames) { kv.frame = frame }
        trail.frame = bounds
        glideLayout = mode == .letters && !context.isPad
            ? GlideDecoder.Layout(keys: keys.compactMap { kv in
                guard let c = kv.spec.char, c.count == 1, let ch = c.first else { return nil }
                return (ch, CGPoint(x: kv.frame.midX, y: kv.frame.midY))
            }, pitch: keyPitch)
            : nil
        layoutKeyGradient()
    }

    /// A gradient theme is one gradient across the whole grid, shown only
    /// through the key shapes: every key carries its slice and the system
    /// sheet stays visible between them.
    private var keyGradientLayer: CAGradientLayer?

    private func layoutKeyGradient() {
        guard let colors = Glass.keyGradient else {
            keyGradientLayer?.removeFromSuperlayer()
            keyGradientLayer = nil
            return
        }
        let gradient = keyGradientLayer ?? CAGradientLayer()
        if keyGradientLayer == nil {
            layer.insertSublayer(gradient, at: 0)
            keyGradientLayer = gradient
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        let shapes = UIBezierPath()
        for kv in keys where !kv.spec.bare {
            shapes.append(UIBezierPath(roundedRect: kv.frame, cornerRadius: Glass.radiusKey))
        }
        let mask = (gradient.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = bounds
        mask.path = shapes.cgPath
        gradient.mask = mask
        CATransaction.commit()
    }

    /// Where a key is, in this view, for the tour's ring.
    func frame(ofKey id: String) -> CGRect? {
        keys.first { $0.spec.id == id }?.frame
    }

    // MARK: Shift

    private var lastShiftTap: Date = .distantPast

    func setShift(_ new: ShiftState, auto: Bool) {
        shift = new
        autoShifted = auto
        for kv in keys {
            kv.shifted = shiftActive
            kv.setShiftState(shift)
        }
    }

    /// Called by the VC when the text context changes (autocapitalize).
    func syncAutoShift(wantsCapital: Bool) {
        guard mode == .letters else { return }
        // With Auto-capitalize off, the shift the board starts with (a
        // sentence start) is let go too: the first letter of a field came
        // out capital anyway (2026-10-14).
        let wants = wantsCapital && SettingsStore.current.autocapitalize
        if wants, shift == .off {
            setShift(.on, auto: true)
        } else if !wants, shift == .on, autoShifted {
            setShift(.off, auto: false)
        }
    }

    func setMode(_ new: KeyboardMode) {
        mode = new
        rebuild()
    }

    // MARK: Touch routing

    /// The key under a touch. Apple's keyboard has NO dead space: a finger
    /// that lands in a gap, or a hair outside the outermost key, still types
    /// the nearest one. We used to drop those touches — with a 12pt row gap
    /// and only 5pt of give there was a dead band between every row, and at
    /// speed fingers land there constantly. That was the "missing keys".
    private func key(at point: CGPoint) -> KeyView? {
        KeyHit.index(at: point, frames: keys.map(\.frame), pitch: keyPitch,
                     area: bounds)
            .map { keys[$0] }
    }

    /// Where a touch may wander before it stops counting as this key's.
    ///
    /// Anchored to WHERE THE FINGER LANDED as well as to the key. A touch
    /// that came down in a gap was snapped to the nearest key by `key(at:)`,
    /// so it is legitimately OUTSIDE that key's frame — measuring only from
    /// the frame threw it away on the first tremor, and a real finger always
    /// moves. `touchesBegan` accepted the keystroke and `touchesMoved` then
    /// silently dropped it: that is the missing key, and it got worse the
    /// faster you typed.
    private func slack(_ st: TouchState, dx: CGFloat, dy: CGFloat) -> CGRect {
        KeyHit.slack(frame: st.key.frame, start: st.start, dx: dx, dy: dy)
    }

    /// The whole key area is live, the way Apple's keyboard is.
    ///
    /// Keys are not interactive themselves — the container drives every
    /// touch — so a point that missed every key fell straight THROUGH this
    /// view: no touchesBegan, no press, nothing lit up. The gaps between
    /// keys, the margins down each side and the strip beside the indented
    /// middle row were dead at the HIT TEST, long before `key(at:)` could
    /// say which key was nearest. All that careful nearest-key work was
    /// unreachable for exactly the touches it existed to catch.
    ///
    /// Claiming the whole bounds is what makes it reachable. `key(at:)`
    /// still decides WHICH key; this only decides that the touch is ours.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // A real interactive child (the accent popup) gets first refusal.
        if let hit = super.hitTest(point, with: event), hit !== self { return hit }
        return bounds.contains(point) ? self : nil
    }

#if DEBUG
    /// Debug only: runs the real touch decision at a point, including the
    /// small drift every finger makes between down and up.
    ///
    /// This exists because a gap CANNOT be tapped synthetically — the
    /// simulator control and XCUITest both route a tap to an accessibility
    /// element, and a gap has none, so the touch never reaches the process.
    /// Driving the decision directly is the only way to exercise those
    /// coordinates on a simulator.
    func debugTap(at p: CGPoint) {
        guard let kv = key(at: p) else {
            Perf.say("DEBUGTAP (\(p.x),\(p.y)) -> NO KEY")
            return
        }
        let st = TouchState(key: kv, start: p)
        let drift = CGPoint(x: p.x + 1.5, y: p.y + 1.5)
        if !slack(st, dx: 14, dy: 16).contains(drift) {
            Perf.say("DEBUGTAP (\(p.x),\(p.y)) -> \(kv.spec.id) DROPPED on drift")
            return
        }
        Perf.say("DEBUGTAP (\(p.x),\(p.y)) -> \(kv.spec.id)")
        tapAction(kv, event: nil, at: p)
    }
#endif

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            // The phone pad's greyed digits and the number pad's empty
            // corner take the touch and do nothing, as on Apple's.
            guard let kv = key(at: p), !kv.spec.disabled else { continue }
            let st = TouchState(key: kv, start: p, time: touch.timestamp)
            touchStates[ObjectIdentifier(touch)] = st
            kv.setPressed(true)
            feedback(impactStyle: .light, key: kv)

            switch kv.spec.kind {
            case .delete:
                st.mode = .deleteRepeat
                delegate?.kbDeleteBackward()
                startDeleteRepeat(st)
            case .char(let c):
                // Bindings rest while the keys type into Glyf's own fields
                // (a note, a search, an event title) or a password: a hold
                // there is a letter's accents, never a swap of the keyboard.
                let bound = kv.spec.pad || delegate?.kbBindingsLive() == false
                    ? nil : SettingsStore.current.bindings[c]
                if bound != nil {
                    kv.startChargeRing()
                }
                if bound != nil || !kv.spec.accents.isEmpty {
                    st.holdTimer = Timer.scheduledTimer(
                        withTimeInterval: Glass.Ripple.holdThreshold, repeats: false
                    ) { [weak self, weak st] _ in
                        guard let self, let st else { return }
                        self.holdFired(st, boundGlyf: bound)
                    }
                }
            case .space:
                st.mode = .space
                st.space = SpaceGesture(x: p.x, y: p.y, time: touch.timestamp)
                // The same purple ring a glyf key shows, from the first
                // moment (Arpit, 2026-09-30: "the space bar should also have
                // that purple thing on pressing like other glyf keys"); it
                // had waited 0.1 s, so a tap never showed it.
                kv.startChargeRing(duration: SpaceGesture.holdThreshold)
                st.holdTimer = Timer.scheduledTimer(
                    withTimeInterval: SpaceGesture.holdThreshold, repeats: false
                ) { [weak self, weak st] _ in
                    guard let self, let st, let effects = st.space?.holdElapsed() else { return }
                    self.perform(effects, for: st, event: nil)
                }
            case .ret:
                // Held, return is a new line even where it sends (Arpit,
                // 2026-10-08: "hold return i need in ios too").
                st.holdTimer = Timer.scheduledTimer(
                    withTimeInterval: Glass.Ripple.holdThreshold + 0.08, repeats: false
                ) { [weak self, weak st] _ in
                    guard let self, let st else { return }
                    st.mode = .holdFired
                    self.feedback(impactStyle: .light)
                    self.delegate?.kbReturnHeld()
                }
            case .globe:
                st.holdTimer = Timer.scheduledTimer(
                    withTimeInterval: Glass.Ripple.holdThreshold, repeats: false
                ) { [weak self, weak st] _ in
                    guard let self, let st else { return }
                    st.mode = .holdFired
                    self.delegate?.kbGlobe(event: event, key: st.key, longPress: true)
                }
            default:
                break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let st = touchStates[ObjectIdentifier(touch)] else { continue }
            let p = touch.location(in: self)
            switch st.mode {
            case .accentPopup:
                st.popup?.track(pointInSuperview: p)
            case .space:
                guard var gesture = st.space else { break }
                // Leaving the bar vertically before any glide or hold is a
                // cancel, same as every other key. Once gliding, the whole
                // keyboard is the trackpad.
                if gesture.isUndecided(at: touch.timestamp),
                   abs(p.x - st.start.x) <= SpaceGesture.swipeSlop,
                   !st.key.frame.insetBy(dx: -14, dy: -16).contains(p) {
                    st.holdTimer?.invalidate()
                    st.key.cancelChargeRing()
                    st.key.setPressed(false)
                    st.mode = .slidAway
                    break
                }
                let effects = gesture.moved(x: p.x, y: p.y, time: touch.timestamp)
                st.space = gesture
                perform(effects, for: st, event: event)
            case .pending:
                if canGlide(st) {
                    // A letter the finger leaves at speed is the start of a
                    // word, not a slip off the key: nothing is cancelled, and
                    // past the threshold the touch glides.
                    if hypot(p.x - st.start.x, p.y - st.start.y) >= Self.glideStart * keyPitch {
                        beginGlide(st, at: p, time: touch.timestamp)
                    }
                } else if !slack(st, dx: 14, dy: 16).contains(p) {
                    st.holdTimer?.invalidate()
                    st.key.cancelChargeRing()
                    st.key.setPressed(false)
                    st.mode = .slidAway
                }
            case .glide:
                glideMoved(st, to: p, time: touch.timestamp)
            case .deleteRepeat:
                if !slack(st, dx: 20, dy: 24).contains(p) {
                    st.repeatTimer?.invalidate()
                }
            default:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let st = touchStates.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            defer { st.invalidate() }
            st.key.setPressed(false)
            st.key.cancelChargeRing()

            switch st.mode {
            case .holdFired, .slidAway, .deleteRepeat:
                continue
            case .space:
                guard var gesture = st.space else { continue }
                // The lift can carry travel no touchesMoved reported (a fast
                // flick): apply it before deciding what the gesture was.
                let p = touch.location(in: self)
                let effects = gesture.moved(x: p.x, y: p.y, time: touch.timestamp)
                    + gesture.ended(time: touch.timestamp)
                st.space = gesture
                perform(effects, for: st, event: event)
            case .accentPopup:
                if let sel = st.popup?.selected {
                    insertFromKey(sel)
                }
                continue
            case .glide:
                glideEnded(st, at: touch.location(in: self), time: touch.timestamp)
            case .pending:
                tapAction(st.key, event: event, at: st.start)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let st = touchStates.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            st.key.setPressed(false)
            st.key.cancelChargeRing()
            st.invalidate()
            if st.mode == .space, var gesture = st.space {
                let effects = gesture.cancelled()
                st.space = gesture
                perform(effects, for: st, event: event)
            }
            if st.mode == .glide {
                st.lit?.updateFill(pressed: false)
                trail.end()
            }
        }
    }

    // MARK: Glide typing (Arpit, 2026-10-07: "its guesses needs to be perfect too")

    /// A letter on the letter layer, with glide typing on and a field that
    /// takes it. Space keeps its own gestures; pads and symbols have none.
    private func canGlide(_ st: TouchState) -> Bool {
        guard glideLayout != nil, mode == .letters, !st.key.spec.pad,
              let c = st.key.spec.char, c.count == 1, let a = c.first?.asciiValue, a >= 97, a <= 122,
              SettingsStore.current.glideTyping != false else { return false }
        return delegate?.kbGlideAllowed() ?? false
    }

    private func glidePoint(_ p: CGPoint, time: TimeInterval) -> GlidePoint {
        GlidePoint(x: Float(p.x / keyPitch), y: Float(p.y / keyPitch), t: time)
    }

    private func beginGlide(_ st: TouchState, at p: CGPoint, time: TimeInterval) {
        st.holdTimer?.invalidate()
        st.key.cancelChargeRing()
        st.key.setPressed(false)
        st.mode = .glide
        st.path = [glidePoint(st.start, time: st.startTime)]
        trail.begin(at: st.start, time: st.startTime)
        glideMoved(st, to: p, time: time)
    }

    private func glideMoved(_ st: TouchState, to p: CGPoint, time: TimeInterval) {
        st.path.append(glidePoint(p, time: time))
        trail.extend(to: p, time: time)
        // The key under the finger lights, lightly: the fill, no balloon.
        let under = key(at: p)
        if under !== st.lit {
            st.lit?.updateFill(pressed: false)
            if let under, under.spec.isChar { under.updateFill(pressed: true); st.lit = under } else { st.lit = nil }
        }
        // The word so far, worked out a few times a second, not per sample.
        guard let layout = glideLayout, time - st.decodedAt >= 0.09 else { return }
        st.decodedAt = time
        trail.show(delegate?.kbGlideMoved(st.path, layout: layout), over: p)
    }

    private func glideEnded(_ st: TouchState, at p: CGPoint, time: TimeInterval) {
        st.path.append(glidePoint(p, time: time))
        st.lit?.updateFill(pressed: false)
        trail.end()
        guard let layout = glideLayout else { return }
        delegate?.kbGlideEnded(st.path, layout: layout)
        if shift == .on { setShift(.off, auto: false) } // shift releases after one word
        delegate?.kbTextInteraction()
    }

    // MARK: Space bar outcomes (SpaceGesture decides, the view performs)

    private func perform(_ effects: [SpaceGesture.Effect], for st: TouchState, event: UIEvent?) {
        for effect in effects {
            switch effect {
            case .beginGlide:
                st.holdTimer?.invalidate()
                st.key.cancelChargeRing()
                st.key.setPressed(false)
                st.glides = delegate?.kbSpaceGestures().glide ?? true
                guard st.glides else { break }
                setTrackpadLook(true)
                feedback(impactStyle: .light, click: false)
                delegate?.kbCursorGlideBegan()
            case .moveCursor(let graphemes):
                if st.glides { delegate?.kbMoveCursor(graphemes: graphemes) }
            case .endGlide:
                guard st.glides else { break }
                setTrackpadLook(false)
                delegate?.kbCursorGlideEnded()
            case .openBar:
                st.key.setPressed(false)
                if delegate?.kbSpaceGestures().bar ?? true {
                    igniteRipple(from: st.key)
                    delegate?.kbSpaceHoldIgnited(origin: st.key)
                } else {
                    tapAction(st.key, event: event)
                }
            case .typeSpace:
                tapAction(st.key, event: event)
            }
        }
    }

    /// Apple's trackpad look: every key face goes blank while the cursor
    /// glides, so the board reads as a surface, not keys.
    private func setTrackpadLook(_ on: Bool) {
        for kv in keys { kv.setFaceHidden(on) }
    }

    private func tapAction(_ kv: KeyView, event: UIEvent?, at point: CGPoint? = nil) {
        // A theme's sample already sounded on the way down; only the system
        // click is asked for again on the lift.
        if ThemeSound.shared.sample(for: Self.soundRole(kv)) == nil { UIDevice.current.playInputClick() }
        switch kv.spec.kind {
        case .char(let c):
            lastTapOffset = point.map { p in
                (Float((p.x - kv.frame.midX) / keyPitch), Float((p.y - kv.frame.midY) / keyPitch))
            }
            // ".com" and the pad's symbols type as they are, shift or not.
            insertFromKey(shiftActive && c.count == 1 && !kv.spec.pad ? c.uppercased() : c)
            lastTapOffset = nil
            // Apple's: an apostrophe from the symbols goes straight back to letters.
            if mode != .letters, c == "'" { setMode(.letters) }
        case .space:
            delegate?.kbSpaceTapped()
            // "at 5 pm": a space after numbers or symbols brings the letters back.
            if mode != .letters { setMode(.letters) }
        case .ret:
            delegate?.kbReturnTapped()
        case .shift:
            let now = Date()
            if now.timeIntervalSince(lastShiftTap) < 0.3 {
                setShift(.capsLock, auto: false)
            } else {
                setShift(shift == .off ? .on : .off, auto: false)
            }
            lastShiftTap = now
        case .mode(let m):
            switch m {
            // On the phone pad "+*#" opens its second page and "123" comes back.
            case "123": setMode(context.isPad ? .letters : .symbols1)
            case "+*#": setMode(.symbols1)
            case "ABC": setMode(.letters)
            case "#+=": setMode(.symbols2)
            default: break
            }
        case .globe:
            delegate?.kbGlobe(event: event, key: kv, longPress: false)
        case .emoji:
            delegate?.kbOpenEmoji()
        case .delete:
            break // handled on touch-down
        }
    }

    private func insertFromKey(_ text: String) {
        delegate?.kbInsert(text)
        if shift == .on { setShift(.off, auto: false) } // shift releases after one char
        delegate?.kbTextInteraction()
    }

    // MARK: Hold outcomes

    private func holdFired(_ st: TouchState, boundGlyf: String?) {
        guard st.mode == .pending else { return }
        if let glyfId = boundGlyf, let c = st.key.spec.char {
            st.mode = .holdFired
            st.key.setPressed(false)
            igniteRipple(from: st.key)
            delegate?.kbBoundKeyIgnited(keyId: c, glyfId: glyfId, origin: st.key)
        } else if !st.key.spec.accents.isEmpty, let c = st.key.spec.char {
            st.mode = .accentPopup
            let popup = AccentPopup(base: c, accents: st.key.spec.accents, shifted: shiftActive)
            addSubview(popup)
            popup.place(over: st.key.frame, in: bounds.insetBy(dx: 0, dy: -Glass.toolbarHeight))
            st.popup = popup
            feedback(impactStyle: .light)
        }
    }

    private func startDeleteRepeat(_ st: TouchState) {
        st.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak st] _ in
            guard let self, let st else { return }
            self.tickDeleteRepeat(st)
        }
    }

    private func tickDeleteRepeat(_ st: TouchState) {
        delegate?.kbDeleteBackward()
        st.repeatCount += 1
        // Accelerating repeat (§6.1): 90ms → 45ms after ~18 repeats.
        let interval: TimeInterval = st.repeatCount > 18 ? 0.045 : 0.09
        st.repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self, weak st] _ in
            guard let self, let st else { return }
            self.tickDeleteRepeat(st)
        }
        // Every 4th repeat, and only a short key sound, never a long one.
        if st.repeatCount % 4 == 0, !(SettingsStore.current.keyClicks && ThemeSound.shared.play(.delete)) {
            UIDevice.current.playInputClick()
        }
    }

    // MARK: Ripple (§5.3 — staggered per-key tint, LUT, no offscreen passes)

    func igniteRipple(from origin: KeyView) {
        feedback(impactStyle: .medium)
        if Glass.reduceMotion {
            // Accessibility path: haptic + 120ms origin flash, no propagation.
            origin.igniteOrigin()
            DispatchQueue.main.asyncAfter(deadline: .now() + Glass.Ripple.reducedMotionFlash) {
                origin.settleFromIgnition()
            }
            return
        }
        origin.igniteOrigin()
        let o = origin.center
        let now = CACurrentMediaTime()
        var maxDelay: TimeInterval = 0
        for kv in keys where kv !== origin {
            let d = hypot(kv.center.x - o.x, kv.center.y - o.y) / max(unitWidth + 6, 1)
            let delay = d * Glass.Ripple.delayPerUnit
            maxDelay = max(maxDelay, delay)
            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.values = [0, 0.55, 0]
            anim.keyTimes = [0, 0.5, 1]
            anim.duration = Glass.Ripple.perKeyTint * 2
            anim.beginTime = now + delay
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            kv.tintLayer.add(anim, forKey: "ripple")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + maxDelay + Glass.Ripple.perKeyTint) {
            origin.settleFromIgnition()
        }
    }

    // MARK: Feedback

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    private func feedback(impactStyle: UIImpactFeedbackGenerator.FeedbackStyle, click: Bool = true,
                          key: KeyView? = nil) {
        let s = SettingsStore.current
        if click, s.keyClicks {
            // A theme's own sound on key down (docs/THEMES.md §4.3), else the
            // system click.
            if !(key.map { ThemeSound.shared.play(Self.soundRole($0)) } ?? false) {
                UIDevice.current.playInputClick()
            }
        }
        guard s.haptics else { return }
        switch impactStyle {
        case .medium: mediumImpact.impactOccurred()
        default: lightImpact.impactOccurred()
        }
        // The Taptic Engine idles down between taps, and a cold one answers
        // late — which reads as the key itself being late. Warming it for the
        // next keystroke is what keeps fast typing feeling immediate.
        warmHaptics()
    }

    /// Which of a sound pack's samples a key plays.
    private static func soundRole(_ kv: KeyView) -> ThemeSoundRole {
        switch kv.spec.kind {
        case .space: return .space
        case .delete: return .delete
        case .ret: return .ret
        default: return .letter
        }
    }

    /// Keep the engine ready while someone is typing. Cheap, and iOS drops
    /// it back to idle on its own a moment after the last call.
    private func warmHaptics() {
        guard SettingsStore.current.haptics else { return }
        lightImpact.prepare()
    }
}
