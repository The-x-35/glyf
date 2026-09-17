import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'orb.dart';

/// The glass orb, talking: it glows and breathes while its words appear, the
/// way a voice assistant shows it is speaking, and settles when it is done.
class TalkingOrb extends StatefulWidget {
  const TalkingOrb({super.key, required this.lines, this.size = 132, this.onDone});

  /// Said one after another, each typed out.
  final List<String> lines;
  final double size;
  final VoidCallback? onDone;

  @override
  State<TalkingOrb> createState() => _TalkingOrbState();
}

class _TalkingOrbState extends State<TalkingOrb> with TickerProviderStateMixin {
  late final AnimationController _voice =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final List<String> _shown = [];
  String _typing = '';
  bool _speaking = false;
  Timer? _timer;

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
      _typing = '';
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
      var i = 0;
      _timer = Timer.periodic(const Duration(milliseconds: 26), (t) {
        if (!mounted) {
          t.cancel();
          if (!done.isCompleted) done.complete();
          return;
        }
        i = math.min(line.length, i + 1);
        setState(() => _typing = line.substring(0, i));
        if (i >= line.length) {
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
        _typing = '';
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
        builder: (context, child) {
          final v = Curves.easeInOut.transform(_voice.value);
          return Stack(alignment: Alignment.center, children: [
            // The voice: a soft ring that swells as it talks.
            Container(
              width: widget.size * (1.08 + 0.16 * v),
              height: widget.size * (1.08 + 0.16 * v),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Glass.accent.withValues(alpha: _speaking ? 0.20 * (0.5 + v) : 0.06),
                  Glass.accent.withValues(alpha: 0),
                ]),
              ),
            ),
            Transform.scale(scale: 1 + 0.035 * v, child: child),
          ]);
        },
        child: GlassOrb(size: widget.size, label: 'g'),
      ),
      const SizedBox(height: 18),
      for (final line in _shown) _line(line),
      if (_typing.isNotEmpty) _line(_typing),
    ]);
  }

  Widget _line(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 21, height: 1.3, fontWeight: FontWeight.w700, color: Glass.ink, letterSpacing: -0.3),
        ),
      );
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
