import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
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
  });

  /// Said one after another, each typed out. The first is the title.
  /// `{glyf}` in a line is the Glyf wordmark, appearing as one piece.
  final List<String> lines;
  final double size;
  final double titleSize;
  final VoidCallback? onDone;

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

  @override
  void initState() {
    super.initState();
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
    _timer?.cancel();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    setState(() => _speaking = true);
    if (!reduce) _voice.repeat(reverse: true);
    for (final line in widget.lines) {
      if (reduce) {
        _shown.add(line);
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
      await Future.delayed(const Duration(milliseconds: 380));
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
          return Transform.scale(
            scale: 1 + 0.03 * v,
            child: GlassOrb(size: widget.size, energy: v),
          );
        },
      ),
      SizedBox(height: widget.size * 0.06),
      for (var i = 0; i < _shown.length; i++) _line(_shown[i], title: i == 0),
      if (_typingLine != null && _typed > 0)
        _line(_typingLine!, title: _shown.isEmpty, upTo: _typed),
    ]);
  }

  Widget _line(String text, {required bool title, int? upTo}) {
    final style = title
        ? TextStyle(fontSize: widget.titleSize, height: 1.15, fontWeight: FontWeight.w700, color: Glass.ink, letterSpacing: -widget.titleSize * 0.03)
        : TextStyle(fontSize: widget.titleSize * 0.56, height: 1.35, fontWeight: FontWeight.w400, color: Glass.inkSoft);
    final pieces = _pieces(text);
    final shown = pieces.take(upTo ?? pieces.length).toList();
    final spans = <InlineSpan>[];
    final run = StringBuffer();
    void flush() {
      if (run.isEmpty) return;
      spans.add(TextSpan(text: run.toString()));
      run.clear();
    }
    for (final p in shown) {
      if (p == _mark) {
        flush();
        final size = style.fontSize! * 1.04;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          // Room on the right for the wordmark's dot, which rides past the f.
          child: Padding(
            padding: EdgeInsets.only(left: size * 0.06, right: size * (GlyfWordmark.gapRatio + GlyfWordmark.dotRatio)),
            child: GlyfWordmark(size: size),
          ),
        ));
      } else {
        run.write(p);
      }
    }
    flush();
    return Padding(
      padding: EdgeInsets.only(bottom: title ? 10 : 4),
      child: Semantics(
        label: text.replaceAll(_mark, 'Glyf'),
        child: ExcludeSemantics(
          child: Text.rich(TextSpan(children: spans), textAlign: TextAlign.center, style: style),
        ),
      ),
    );
  }
}

/// A few seconds of the thing the orb is talking about: a friend asks for an
/// address, the keyboard offers it, one tap sends it. On a loop.
class RememberDemo extends StatefulWidget {
  const RememberDemo({super.key, this.address = 'Flat 4B, Palm Grove, Bandra West'});
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
        final ask = Curves.easeOutBack.transform(_between(v, 0.02, 0.12));
        final strip = Curves.easeOutCubic.transform(_between(v, 0.22, 0.32));
        final press = _between(v, 0.42, 0.50);
        final sent = Curves.easeOutBack.transform(_between(v, 0.52, 0.62));
        final out = 1 - _between(v, 0.90, 0.98);
        final pressed = press > 0 && sent == 0;
        return Opacity(
          opacity: out,
          child: Container(
            height: 214,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Glass.hairline),
              boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 24, offset: Offset(0, 10))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
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
            ]),
          ),
        );
      },
    );
  }

  Widget _bubble(String text, {required bool mine}) => Container(
        constraints: const BoxConstraints(maxWidth: 230),
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF0A84FF) : const Color(0xFFE9E9EB),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(text, style: TextStyle(fontSize: 14.5, color: mine ? Colors.white : Colors.black)),
      );
}
