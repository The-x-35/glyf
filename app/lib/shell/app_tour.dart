import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Profile's "Take the tour" asks the shell for the tour by bumping this.
final appTourRequests = ValueNotifier<int>(0);

/// The Home pieces the tour rings, handed to HomeTab so it can mark them.
class HomeTourKeys {
  final keyboard = GlobalKey(debugLabel: 'tour:keyboard');
  final firstKey = GlobalKey(debugLabel: 'tour:first-key');
  final tryField = GlobalKey(debugLabel: 'tour:try');
}

/// One stop on the app tour: what to ring, and what to say there. The last
/// stop has no target: its card sits in the middle and offers the chats.
class AppTourStep {
  const AppTourStep({required this.target, required this.title, required this.body});

  final GlobalKey? target;
  final String title;
  final String body;
}

/// The floating button on Home that starts the tour (Arpit, 2026-10-06: "we
/// wont have a tour screen, we will have a floating button to take a tour in
/// the main screen of app"). Its ✕ puts it away; Profile › Tour keeps the
/// tour within reach.
class TakeTourButton extends StatelessWidget {
  const TakeTourButton({super.key, required this.onTap, required this.onDismiss});

  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Glass.ink,
      shape: const StadiumBorder(),
      elevation: 8,
      shadowColor: const Color(0x55000000),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          identifier: 'tour:start',
          button: true,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.explore_rounded, size: 19, color: Colors.white),
                SizedBox(width: 8),
                Text('Take a tour',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
        Semantics(
          identifier: 'tour:dismiss',
          button: true,
          label: 'Hide the tour button',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onDismiss,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 10, 8),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 15, color: Colors.white70),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The app tour: the screen dims except a ring round one thing at a time,
/// and a card says what it is. Next (or a tap on the ring) walks on; the
/// last card offers the chats, the website's, played on the real keyboard.
class AppTourOverlay extends StatefulWidget {
  const AppTourOverlay({super.key, required this.steps, required this.onEnd});

  final List<AppTourStep> steps;

  /// True: start the chats. False: skipped, or "Later" on the last card.
  final void Function(bool chats) onEnd;

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay> with SingleTickerProviderStateMixin {
  int _at = 0;
  Rect? _hole;
  final _self = GlobalKey();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show(0));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Brings the stop's target on screen (Home scrolls on a small phone),
  /// then measures it once it has settled.
  Future<void> _show(int i) async {
    setState(() {
      _at = i;
      _hole = null;
    });
    final ctx = widget.steps[i].target?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 260), alignment: 0.3, curve: Curves.easeOutCubic);
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted || _at != i) return;
    setState(() => _hole = _measure(widget.steps[i].target));
  }

  Rect? _measure(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final me = _self.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || me == null || !box.hasSize || !box.attached) return null;
    return (box.localToGlobal(Offset.zero, ancestor: me) & box.size).inflate(8);
  }

  void _next() {
    if (_at < widget.steps.length - 1) _show(_at + 1);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_at];
    final last = _at == widget.steps.length - 1;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final hole = step.target == null ? null : _hole;
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        key: _self,
        builder: (context, box) {
          final size = box.biggest;
          final padding = MediaQuery.paddingOf(context);
          final cardWidth = math.min(size.width - 32, 380.0);
          // Under the ring when there's room, else over it; the last card
          // (and a stop still being measured) sits in the middle.
          const cardRoom = 190.0;
          double? top;
          double? bottom;
          if (hole != null) {
            if (hole.bottom + 14 + cardRoom < size.height - padding.bottom) {
              top = hole.bottom + 14;
            } else {
              bottom = size.height - hole.top + 14;
            }
          }
          final card = _TourCard(
            width: cardWidth,
            step: step,
            count: last ? null : '${_at + 1} of ${widget.steps.length - 1}',
            last: last,
            onNext: last ? () => widget.onEnd(true) : _next,
            onSkip: () => widget.onEnd(false),
          );
          return Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  if (hole != null && hole.contains(d.localPosition)) _next();
                },
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    painter: _ScrimPainter(hole: hole, t: still ? 0.25 : _pulse.value),
                  ),
                ),
              ),
            ),
            // A stop still being measured shows no card yet: it would jump.
            if (step.target != null && hole == null)
              const SizedBox.shrink()
            else if (top != null || bottom != null)
              Positioned(
                left: (size.width - cardWidth) / 2,
                top: top,
                bottom: bottom,
                child: card,
              )
            else
              Center(child: card),
          ]);
        },
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.width,
    required this.step,
    required this.count,
    required this.last,
    required this.onNext,
    required this.onSkip,
  });

  final double width;
  final AppTourStep step;
  final String? count;
  final bool last;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'tour:card',
      liveRegion: true,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(step.title,
              style: const TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(step.body, style: const TextStyle(color: Glass.inkSoft, fontSize: 14, height: 1.4)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            if (count != null)
              Text(count!,
                  style: const TextStyle(
                      color: Glass.inkSoft, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
            const Spacer(),
            Semantics(
              identifier: last ? 'tour:later' : 'tour:skip',
              button: true,
              child: TextButton(
                onPressed: onSkip,
                child: Text(last ? 'Later' : 'Skip',
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              identifier: last ? 'tour:chats' : 'tour:next',
              button: true,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Glass.ink,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                onPressed: onNext,
                child: Text(last ? 'Start the chats' : 'Next'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The dim with the ring's hole cut out of it, and the ring breathing.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.t});

  final Rect? hole;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0x8C000000);
    final all = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(all, scrim);
      return;
    }
    final ring = RRect.fromRectAndRadius(h, const Radius.circular(18));
    canvas.drawPath(Path.combine(PathOperation.difference, all, Path()..addRRect(ring)), scrim);
    final glow = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    canvas.drawRRect(
      ring.inflate(3 + 4 * glow),
      Paint()
        ..color = Glass.accent.withValues(alpha: 0.28 * (1 - glow))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..color = Glass.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole || old.t != t;
}
