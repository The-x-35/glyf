import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../launch/launch_overlay.dart';
import 'orb.dart';

/// The glass orb, talking: it glows and breathes while its words appear, the
/// way a voice assistant shows it is speaking, and settles when it is done.
class TalkingOrb extends StatefulWidget {
  const TalkingOrb({
    super.key,
    required this.lines,
    this.size = 132,
    this.titleSize = 30,
    this.onDone,
    this.launchTarget = false,
    this.instant = false,
  });

  /// The first is the title, typed out; the lines after it pop in whole once
  /// it is said. `{glyf}` in a line is the Glyf wordmark, as one piece.
  final List<String> lines;
  final double size;
  final double titleSize;
  final VoidCallback? onDone;

  /// The first screen after launch: the launch bubble lands on this orb, so
  /// it stays hidden, and says nothing, until it has.
  final bool launchTarget;

  /// Already heard (a step come back to): everything shows at once.
  final bool instant;

  @override
  State<TalkingOrb> createState() => _TalkingOrbState();
}

class _TalkingOrbState extends State<TalkingOrb> with TickerProviderStateMixin {
  late final AnimationController _voice =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final List<String> _shown = [];
  /// The line being typed and how many pieces of it are out so far.
  String? _typingLine;
  int _typed = 0;
  bool _speaking = false;
  Timer? _timer;

  static const _mark = '{glyf}';

  /// A line as pieces: each character, and the wordmark as a single piece.
  static List<String> _pieces(String line) {
    final out = <String>[];
    final parts = line.split(_mark);
    for (var i = 0; i < parts.length; i++) {
      out.addAll(parts[i].characters);
      if (i < parts.length - 1) out.add(_mark);
    }
    return out;
  }

  bool get _awaitingLaunch => widget.launchTarget && !LaunchHandoff.done.value;

  @override
  void initState() {
    super.initState();
    if (_awaitingLaunch) {
      LaunchHandoff.done.addListener(_landed);
    } else {
      _speak();
    }
  }

  void _landed() {
    if (!LaunchHandoff.done.value) return;
    LaunchHandoff.done.removeListener(_landed);
    if (!mounted) return;
    setState(() {});
    _speak();
  }

  @override
  void didUpdateWidget(TalkingOrb old) {
    super.didUpdateWidget(old);
    if (old.lines.join('\n') != widget.lines.join('\n')) {
      _timer?.cancel();
      _shown.clear();
      _typingLine = null;
      _speak();
    }
  }

  @override
  void dispose() {
    LaunchHandoff.done.removeListener(_landed);
    _timer?.cancel();
    _voice.dispose();
    super.dispose();
  }

  bool get _still =>
      widget.instant || WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  Future<void> _speak() async {
    if (_still) {
      setState(() => _shown.addAll(widget.lines));
      widget.onDone?.call();
      return;
    }
    setState(() => _speaking = true);
    _voice.repeat(reverse: true);
    for (var index = 0; index < widget.lines.length; index++) {
      final line = widget.lines[index];
      if (index > 0) {
        // After the title, the rest arrives whole, with a small pop.
        await Future.delayed(Duration(milliseconds: index == 1 ? 180 : 120));
        if (!mounted) return;
        setState(() => _shown.add(line));
        await Future.delayed(const Duration(milliseconds: 380));
        if (!mounted) return;
        continue;
      }
      final done = Completer<void>();
      final count = _pieces(line).length;
      var i = 0;
      _typingLine = line;
      _timer = Timer.periodic(const Duration(milliseconds: 26), (t) {
        if (!mounted) {
          t.cancel();
          if (!done.isCompleted) done.complete();
          return;
        }
        i = math.min(count, i + 1);
        setState(() => _typed = i);
        if (i >= count) {
          t.cancel();
          done.complete();
        }
      });
      await done.future;
      if (!mounted) return;
      setState(() {
        _shown.add(line);
        _typingLine = null;
        _typed = 0;
      });
    }
    if (!mounted) return;
    _voice.animateTo(0, duration: const Duration(milliseconds: 400));
    setState(() => _speaking = false);
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _voice,
        builder: (context, _) {
          // The voice: the glow swells and the sphere breathes while it talks.
          final v = _speaking ? Curves.easeInOut.transform(_voice.value) : 0.0;
          return Opacity(
            opacity: _awaitingLaunch ? 0 : 1,
            child: Transform.scale(
              scale: 1 + 0.03 * v,
              child: GlassOrb(
                size: widget.size,
                energy: v,
                // Held still for the launch bubble to land on exactly.
                floating: !_awaitingLaunch,
                sphereKey: widget.launchTarget ? LaunchHandoff.orbKey : null,
              ),
            ),
          );
        },
      ),
      SizedBox(height: widget.size * 0.06),
      // Every line is laid out from the start, the unsaid part invisible, so
      // nothing grows the column and the orb above never moves.
      _line(widget.lines.first,
          title: true,
          upTo: _shown.isNotEmpty ? null : (_typingLine != null ? _typed : 0)),
      for (var i = 1; i < widget.lines.length; i++)
        _popIn(_line(widget.lines[i], title: false), shown: i < _shown.length),
    ]);
  }

  /// A line that pops in once it is said: fades up and grows the last few
  /// percent with a touch of overshoot. Before that it only holds its place.
  Widget _popIn(Widget line, {required bool shown}) {
    if (!shown) return Opacity(opacity: 0, child: line);
    if (_still) return line;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      child: line,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
      ),
    );
  }

  Widget _line(String text, {required bool title, int? upTo}) {
    return Padding(
      padding: EdgeInsets.only(bottom: title ? 10 : 4),
      child: GlyfText(text, style: _style(title), upTo: upTo),
    );
  }

  TextStyle _style(bool title) => title
        ? TextStyle(fontSize: widget.titleSize, height: 1.15, fontWeight: FontWeight.w700, color: Glass.ink, letterSpacing: -widget.titleSize * 0.03)
        : TextStyle(fontSize: widget.titleSize * 0.56, height: 1.35, fontWeight: FontWeight.w400, color: Glass.inkSoft);
}

/// Text where `{glyf}` is the Glyf wordmark, e.g. "Hi, I'm {glyf}".
/// [upTo] shows only the first pieces (characters, the wordmark counting as
/// one) for typing it out; the rest keeps its place, invisible, so the text
/// never reflows as it types.
class GlyfText extends StatelessWidget {
  const GlyfText(this.text, {super.key, required this.style, this.upTo, this.align = TextAlign.center});
  final String text;
  final TextStyle style;
  final int? upTo;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    const mark = _TalkingOrbState._mark;
    final pieces = _TalkingOrbState._pieces(text);
    final visible = upTo ?? pieces.length;
    final spans = <InlineSpan>[];
    final run = StringBuffer();
    var runHidden = false;
    void flush() {
      if (run.isEmpty) return;
      spans.add(TextSpan(
        text: run.toString(),
        style: runHidden ? const TextStyle(color: Color(0x00000000)) : null,
      ));
      run.clear();
    }
    for (var i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      final hidden = i >= visible;
      if (hidden != runHidden) {
        flush();
        runHidden = hidden;
      }
      if (p == mark) {
        flush();
        final size = style.fontSize! * 1.04;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          // Room on the right for the wordmark's dot, which rides past the f.
          child: Opacity(
            opacity: hidden ? 0 : 1,
            child: Padding(
              padding: EdgeInsets.only(left: size * 0.06, right: size * (GlyfWordmark.gapRatio + GlyfWordmark.dotRatio)),
              child: GlyfWordmark(size: size),
            ),
          ),
        ));
      } else {
        run.write(p);
      }
    }
    flush();
    return Semantics(
      label: text.replaceAll(mark, 'Glyf'),
      child: ExcludeSemantics(
        child: Text.rich(TextSpan(children: spans), textAlign: align, style: style),
      ),
    );
  }
}

/// A few seconds of the thing the orb is talking about: a friend asks for an
/// address, the keyboard offers it, one tap sends it. On a loop.
class RememberDemo extends StatefulWidget {
  const RememberDemo({super.key, this.address = '123 Market St, San Francisco'});
  final String address;

  @override
  State<RememberDemo> createState() => _RememberDemoState();
}

class _RememberDemoState extends State<RememberDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 6200))..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  double _between(double v, double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final v = _t.value;
        final ask = Curves.easeOutBack.transform(_between(v, 0.01, 0.10));
        final strip = Curves.easeOutCubic.transform(_between(v, 0.22, 0.32));
        final press = _between(v, 0.42, 0.50);
        final sent = Curves.easeOutBack.transform(_between(v, 0.52, 0.62));
        final out = 1 - _between(v, 0.93, 0.99);
        final pressed = press > 0 && sent == 0;
        // The card itself never fades — only what is playing inside it.
        return _demoCard(
          opacity: out,
          children: [
              Positioned(
                left: 14,
                top: 16,
                child: Transform.scale(
                  alignment: Alignment.bottomLeft,
                  scale: ask,
                  child: _bubble('what\'s your address? 📦', mine: false),
                ),
              ),
              Positioned(
                right: 14,
                top: 66,
                child: Transform.scale(
                  alignment: Alignment.bottomRight,
                  scale: sent,
                  child: _bubble(widget.address, mine: true),
                ),
              ),
              // The keyboard's strip, rising with the saved detail on it.
              Positioned(
                left: 0,
                right: 0,
                bottom: -64 + 64 * strip * (1 - _between(v, 0.62, 0.70)),
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  color: const Color(0xFFE9EAEE),
                  child: AnimatedScale(
                    scale: pressed ? 0.96 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Glass.accent.withValues(alpha: press > 0 ? 0.9 : 0), width: 2),
                      ),
                      child: Row(children: [
                        const Text('Home', style: TextStyle(fontSize: 12.5, color: Glass.inkSoft, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(widget.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, color: Glass.ink)),
                        ),
                        const SizedBox(width: 10),
                        const Text('Insert', style: TextStyle(fontSize: 12.5, color: Glass.accent, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bubble(String text, {required bool mine}) => _chatBubble(text, mine: mine);
}

/// The card every onboarding demo plays inside: white, still, whatever is
/// happening in it.
Widget _demoCard({required double opacity, required List<Widget> children, double height = 214}) => Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Glass.hairline),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 24, offset: Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: Stack(children: children)),
    );

Widget _chatBubble(String text, {required bool mine}) => Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFF0A84FF) : const Color(0xFFE9E9EB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text, style: TextStyle(fontSize: 14.5, color: mine ? Colors.white : Colors.black)),
    );
