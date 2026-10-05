import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// One move of turning Glyf on, shown on the phone's own screen: a band of a
/// real screenshot (tools/setup_guide/make_guide.py crops them), the ring
/// round what to tap there (fractions of the band), and what to do.
class GuideStep {
  const GuideStep(this.image, this.ring, this.say, {this.note});

  /// The file in assets/setup, without ".jpg".
  final String image;
  final Rect ring;
  final String say;

  /// A second, smaller line: where this screen is, or what happens next.
  final String? note;
}

/// iPhone, keyboard not added yet: Glyf's page in Settings (where Open
/// lands on a phone), both switches, Apple's alert, and the way back.
const iosTurnOn = <GuideStep>[
  GuideStep(
    'ios-keyboards-row',
    Rect.fromLTRB(0.033, 0.796, 0.967, 0.957),
    'Tap Keyboards',
    note: 'Settings › Apps › Glyf',
  ),
  GuideStep(
    'ios-glyf-switch',
    Rect.fromLTRB(0.730, 0.239, 0.945, 0.380),
    'Turn on Glyf',
  ),
  GuideStep(
    'ios-full-access-switch',
    Rect.fromLTRB(0.730, 0.398, 0.945, 0.541),
    'Turn on Allow Full Access',
  ),
  GuideStep(
    'ios-allow',
    Rect.fromLTRB(0.498, 0.736, 0.871, 0.901),
    'Tap Allow',
    note: 'Your iPhone restarts Glyf. That’s normal.',
  ),
  GuideStep(
    'ios-back-to-glyf',
    Rect.fromLTRB(0.008, 0.080, 0.158, 0.164),
    'Tap ◀ Glyf to come back',
    note: 'You’ll land right here',
  ),
];

/// iPhone, keyboard added: switching to it, and keeping it first.
const iosUse = <GuideStep>[
  GuideStep(
    'ios-globe-menu',
    Rect.fromLTRB(0.030, 0.132, 0.561, 0.284),
    'Hold 🌐 and pick Glyf',
    note: 'Bottom left, under any keyboard',
  ),
  GuideStep(
    'ios-default-order',
    Rect.fromLTRB(0.043, 0.225, 0.957, 0.422),
    'Make Glyf your default',
    note: 'General › Keyboard › Keyboards › Edit, drag it to the top',
  ),
];

/// iPhone, keyboard added but Full Access not seen yet: switch to Glyf (so
/// it can say whether it has Full Access), and the switch if it hasn't.
const iosAccess = <GuideStep>[
  GuideStep(
    'ios-globe-menu',
    Rect.fromLTRB(0.030, 0.132, 0.561, 0.284),
    'Hold 🌐 and pick Glyf',
    note: 'In the box below',
  ),
  GuideStep(
    'ios-full-access-switch',
    Rect.fromLTRB(0.730, 0.398, 0.945, 0.541),
    'Turn on Allow Full Access',
    note: 'Settings › Apps › Glyf › Keyboards',
  ),
  GuideStep(
    'ios-allow',
    Rect.fromLTRB(0.498, 0.736, 0.871, 0.901),
    'Tap Allow',
    note: 'Your iPhone restarts Glyf. That’s normal.',
  ),
  GuideStep(
    'ios-back-to-glyf',
    Rect.fromLTRB(0.008, 0.080, 0.158, 0.164),
    'Tap ◀ Glyf to come back',
    note: 'You’ll land right here',
  ),
];

/// Android, keyboard not on yet: the switch, Android's two warnings, back.
const androidTurnOn = <GuideStep>[
  GuideStep(
    'android-glyf-switch',
    Rect.fromLTRB(0.820, 0.769, 0.977, 0.890),
    'Turn on Glyf Keyboard',
    note: 'Settings › On-screen keyboard',
  ),
  GuideStep(
    'android-ok',
    Rect.fromLTRB(0.752, 0.587, 0.917, 0.757),
    'Tap OK',
    note: 'Android says this about every keyboard',
  ),
  GuideStep(
    'android-ok-again',
    Rect.fromLTRB(0.752, 0.531, 0.917, 0.702),
    'Tap OK again',
  ),
  GuideStep(
    'android-back',
    Rect.fromLTRB(0.016, 0.056, 0.125, 0.178),
    'Tap ← to come back',
  ),
];

/// Android, keyboard on: picking it is what makes it the phone's keyboard.
const androidPick = <GuideStep>[
  GuideStep(
    'android-pick-glyf',
    Rect.fromLTRB(0.227, 0.525, 0.922, 0.740),
    'Pick Glyf Keyboard',
    note: 'That makes Glyf your keyboard',
  ),
];

/// The steps as a card that turns on its own (a tap turns it sooner): the
/// screenshot with a ring breathing round the thing to tap, and the words
/// under it. It takes the room it is given and steps aside when there isn't
/// enough (the keyboard is up), since the checklist says it in words too.
class SetupGuide extends StatefulWidget {
  const SetupGuide({super.key, required this.steps});

  final List<GuideStep> steps;

  @override
  State<SetupGuide> createState() => _SetupGuideState();
}

class _SetupGuideState extends State<SetupGuide>
    with SingleTickerProviderStateMixin {
  int _at = 0;
  Timer? _turn;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  /// The step's line and a two-line note, with room for larger text.
  static const _captionHeight = 60.0;
  static const _aspect = 1.2;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warm();
  }

  @override
  void didUpdateWidget(SetupGuide old) {
    super.didUpdateWidget(old);
    // The phone moved on to another part of setup: its first step first.
    if (old.steps.map((s) => s.image).join() !=
        widget.steps.map((s) => s.image).join()) {
      _at = 0;
      _warm();
      _schedule();
    }
  }

  /// Decoded ahead, so turning never flashes an empty card.
  void _warm() {
    for (final s in widget.steps) {
      precacheImage(AssetImage('assets/setup/${s.image}.jpg'), context);
    }
  }

  void _schedule() {
    _turn?.cancel();
    if (widget.steps.length < 2) return;
    _turn = Timer(const Duration(milliseconds: 3400), () {
      if (!mounted) return;
      setState(() => _at = (_at + 1) % widget.steps.length);
      _schedule();
    });
  }

  void _go(int by) {
    final n = widget.steps.length;
    if (n < 2) return;
    setState(() => _at = (_at + by + n) % n);
    _schedule();
  }

  @override
  void dispose() {
    _turn?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final step = steps[_at.clamp(0, steps.length - 1)];
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxHeight - _captionHeight - 10;
        if (room < 120) return const SizedBox.shrink();
        final w = math.min(box.maxWidth, math.min(340.0, room * _aspect));
        final h = w / _aspect;
        final ring = Rect.fromLTRB(
          step.ring.left * w,
          step.ring.top * h,
          step.ring.right * w,
          step.ring.bottom * h,
        ).inflate(3);
        return Center(
          child: SizedBox(
            width: w,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  identifier: 'onb:setup:guide',
                  label: '${step.say}. ${step.note ?? ''}',
                  button: steps.length > 1,
                  child: GestureDetector(
                    onTap: () => _go(1),
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v.abs() > 120) _go(v < 0 ? 1 : -1);
                    },
                    child: Container(
                      width: w,
                      height: h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0x14000000)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 22,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: Stack(
                          key: ValueKey(step.image + step.say),
                          children: [
                            Positioned.fill(
                              child: Image.asset(
                                'assets/setup/${step.image}.jpg',
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                excludeFromSemantics: true,
                              ),
                            ),
                            Positioned.fromRect(
                              rect: ring,
                              child: still
                                  ? const _Ring(glow: 0.6)
                                  : _BreathingRing(pulse: _pulse),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: _captionHeight,
                  // Larger text clips here rather than pushing the card out of
                  // the room it was given.
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxHeight: double.infinity,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (steps.length > 1)
                            Container(
                              margin: const EdgeInsets.only(top: 1, right: 9),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Glass.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_at + 1}/${steps.length}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Glass.accent,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.say,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    color: Glass.ink,
                                  ),
                                ),
                                if (step.note != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      step.note!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        height: 1.3,
                                        color: Glass.inkSoft,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BreathingRing extends AnimatedWidget {
  const _BreathingRing({required Animation<double> pulse})
    : super(listenable: pulse);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return _Ring(glow: 0.5 + 0.5 * math.sin(t * 2 * math.pi));
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.glow});

  final double glow;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Glass.accent, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Glass.accent.withValues(alpha: 0.16 + 0.22 * glow),
            blurRadius: 5 + 9 * glow,
            spreadRadius: 1 + 2 * glow,
          ),
        ],
      ),
    ),
  );
}
