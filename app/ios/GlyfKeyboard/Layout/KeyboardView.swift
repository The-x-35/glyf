import UIKit

protocol KeyboardViewDelegate: AnyObject {
    func kbInsert(_ text: String)
    func kbDeleteBackward()
    func kbSpaceTapped()
    func kbReturnTapped()
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
    func kbTextInteraction()
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

    private enum TouchMode { case pending, space, accentPopup, holdFired, slidAway, deleteRepeat }

    private final class TouchState {
        let key: KeyView
        let start: CGPoint
        var mode: TouchMode = .pending
        var holdTimer: Timer?
        var repeatTimer: Timer?
        var repeatCount = 0
        var space: SpaceGesture?
        /// False when the glide started over an in-keyboard editor.
        var glides = true
        var popup: AccentPopup?
        init(key: KeyView, start: CGPoint) { self.key = key; self.start = start }
        func invalidate() {
            holdTimer?.invalidate()
            repeatTimer?.invalidate()
            popup?.removeFromSuperview()
        }
    }

    private var touchStates: [ObjectIdentifier: TouchState] = [:]

    init() {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Build + layout

    var needsGlobe = false
    /// The focused field's flavor — email/URL space rows, digit pads (§6.1).
    var context: KeyboardContext = .text {
        didSet { if context != oldValue { rebuild() } }
    }

    func rebuild() {
        keys.forEach { $0.removeFromSuperview() }
        keys = []
        let s = SettingsStore.current
        rows = KeyboardLayout.rows(mode: mode, numberRow: s.numberRow && mode == .letters,
                                   globe: needsGlobe, context: context)
        for row in rows {
            for spec in row {
                let kv = KeyView(spec: spec)
                kv.isUserInteractionEnabled = false // container drives touches
                if let c = spec.char { kv.isBound = s.bindings[c] != nil }
                kv.shifted = shiftActive
                kv.setShiftState(shift)
                addSubview(kv)
                keys.append(kv)
            }
        }
        setNeedsLayout()
    }

    func refreshBindings() {
        let s = SettingsStore.current
        for kv in keys {
            if let c = kv.spec.char { kv.isBound = s.bindings[c] != nil }
        }
    }

    private var shiftActive: Bool { shift != .off }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !rows.isEmpty, bounds.width > 100 else { return }
        let s = SettingsStore.current
        // Measured off the system keyboard on a 402pt phone (iOS 26): the
        // keys sit on a 10-column grid, 6.5pt side margins, 39.5pt column
        // pitch, 6pt gaps → 33.5pt letters, 54pt rows, 42pt tall. Matching
        // this to the point is what keeps muscle memory intact.
        let hGap: CGFloat = 6
        let vGap: CGFloat = 12
        var left: CGFloat = 6.5
        var right: CGFloat = 6.5
        if s.oneHanded == "left" { right += 56 }
        if s.oneHanded == "right" { left += 56 }
        let availW = bounds.width - left - right
        // Digit pads have 3 wide columns; QWERTY sizes off 10 columns.
        let columns: CGFloat = context.isPad ? 3 : 10
        let padInset: CGFloat = context.isPad ? 80 : 0
        keyPitch = (availW - padInset + hGap) / columns
        unitWidth = keyPitch - hGap
        let rowH = bounds.height / CGFloat(rows.count)
        let keyH = min(rowH - vGap, context.isPad ? 50 : .greatestFiniteMagnitude)
        rowHeight = rowH

        var idx = 0
        for (r, row) in rows.enumerated() {
            let fixedUnits = row.map { $0.units }.filter { $0 > 0 }.reduce(0, +)
            let flexUnits = max(1, columns - fixedUnits)
            let rowUnits = row.contains { $0.units < 0 } ? columns : fixedUnits
            let rowWidth = rowUnits * keyPitch - hGap
            var x = left + (availW - rowWidth) / 2
            let y = CGFloat(r) * rowH + vGap / 2
            for spec in row {
                let units = spec.units < 0 ? flexUnits : spec.units
                let air = spec.gapUnits * keyPitch
                let w = units * keyPitch - hGap - air
                keys[idx].frame = CGRect(x: spec.gapLeading ? x + air : x, y: y,
                                         width: w, height: keyH)
                x += units * keyPitch
                idx += 1
            }
        }
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
        guard mode == .letters, SettingsStore.current.autocapitalize else { return }
        if wantsCapital, shift == .off {
            setShift(.on, auto: true)
        } else if !wantsCapital, shift == .on, autoShifted {
            setShift(.off, auto: false)
        }
    }

    func setMode(_ new: KeyboardMode) {
        mode = new
        rebuild()
    }

    // MARK: Touch routing

    private func key(at point: CGPoint) -> KeyView? {
        keys.first { $0.frame.insetBy(dx: -3, dy: -5).contains(point) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            guard let kv = key(at: p) else { continue }
            let st = TouchState(key: kv, start: p)
            touchStates[ObjectIdentifier(touch)] = st
            kv.setPressed(true)
            feedback(impactStyle: .light)

            switch kv.spec.kind {
            case .delete:
                st.mode = .deleteRepeat
                delegate?.kbDeleteBackward()
                startDeleteRepeat(st)
            case .char(let c):
                let bound = SettingsStore.current.bindings[c]
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
                kv.startChargeRing(duration: SpaceGesture.holdThreshold - 0.1, delay: 0.1)
                st.holdTimer = Timer.scheduledTimer(
                    withTimeInterval: SpaceGesture.holdThreshold, repeats: false
                ) { [weak self, weak st] _ in
                    guard let self, let st, let effects = st.space?.holdElapsed() else { return }
                    self.perform(effects, for: st, event: nil)
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
                if !st.key.frame.insetBy(dx: -14, dy: -16).contains(p) {
                    st.holdTimer?.invalidate()
                    st.key.cancelChargeRing()
                    st.key.setPressed(false)
                    st.mode = .slidAway
                }
            case .deleteRepeat:
                if !st.key.frame.insetBy(dx: -20, dy: -24).contains(p) {
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
        }
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
        UIDevice.current.playInputClick()
        switch kv.spec.kind {
        case .char(let c):
            lastTapOffset = point.map { p in
                (Float((p.x - kv.frame.midX) / keyPitch), Float((p.y - kv.frame.midY) / keyPitch))
            }
            insertFromKey(shiftActive ? c.uppercased() : c)
            lastTapOffset = nil
        case .space:
            delegate?.kbSpaceTapped()
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
            case "123": setMode(.symbols1)
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
        if st.repeatCount % 4 == 0 { UIDevice.current.playInputClick() }
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

    private func feedback(impactStyle: UIImpactFeedbackGenerator.FeedbackStyle, click: Bool = true) {
        let s = SettingsStore.current
        if click, s.keyClicks { UIDevice.current.playInputClick() }
        guard s.haptics else { return }
        switch impactStyle {
        case .medium: mediumImpact.impactOccurred()
        default: lightImpact.impactOccurred()
        }
    }
}
