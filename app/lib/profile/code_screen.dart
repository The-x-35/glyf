import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// "Got a code?": six letters and numbers from Arpit, a month or a year of
/// a plan. The server checks the code and puts the plan on the account
/// (`POST /codes/redeem`); a code works once. Pops true when one was used.
class CodeScreen extends StatefulWidget {
  const CodeScreen({super.key});

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> with SingleTickerProviderStateMixin {
  static const _length = 6;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));
  bool _busy = false;
  String? _error;
  CodeRedeemed? _done;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _focus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  String get _code => _controller.text;
  String _last = '';

  void _changed() {
    // Focus and selection moves fire here too; only an edit counts, or a
    // wrong code would be sent again the moment the field got focus back.
    if (_code == _last) return;
    _last = _code;
    setState(() => _error = null);
    // The sixth character applies it, the way a verification code does.
    if (_code.length == _length && !_busy) _apply();
  }

  Future<void> _apply() async {
    if (_code.length != _length || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await GlyfApi.redeemCode(_code);
      await GlyfBridge.updateSharedSettings((s) {
        s['plan'] = done.plan;
        s['proUnlocked'] = done.plan != 'free';
        return s;
      });
      Telemetry.log('code_redeemed', {'plan': done.codePlan, 'days': done.days});
      HapticFeedback.mediumImpact();
      _focus.unfocus();
      if (mounted) setState(() => _done = done);
    } on GlyfApiException catch (e) {
      _fail(e.message);
    } on SocketException {
      _fail("Couldn't reach Glyf. Try again");
    } on TimeoutException {
      _fail("Couldn't reach Glyf. Try again");
    } catch (_) {
      _fail("Couldn't use the code right now. Try again");
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _error = message;
    });
    _shake.forward(from: 0);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(children: [
        SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            child: done == null ? _entry() : _success(done),
          ),
        ),
        if (done != null && !MediaQuery.of(context).disableAnimations)
          const Positioned.fill(child: IgnorePointer(child: Confetti())),
      ]),
    );
  }

  Widget _entry() {
    return Padding(
      key: const ValueKey('entry'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Enter your code',
            style: TextStyle(color: Glass.ink, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('6 letters and numbers',
            style: TextStyle(color: Glass.inkSoft, fontSize: 15)),
        const SizedBox(height: 28),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(math.sin(_shake.value * math.pi * 6) * 9 * (1 - _shake.value), 0),
            child: child,
          ),
          child: _boxes(),
        ),
        SizedBox(
          height: 44,
          child: Center(
            child: AnimatedOpacity(
              opacity: _error == null ? 0 : 1,
              duration: const Duration(milliseconds: 160),
              child: Semantics(
                identifier: 'code:error',
                liveRegion: true,
                child: Text(_error ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Glass.danger, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
        const Spacer(),
        Semantics(
          identifier: 'code:apply',
          button: true,
          child: _busy
              ? const SizedBox(
                  height: 52,
                  child: Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink))))
              : PillButton(label: 'Apply', onPressed: _code.length == _length ? _apply : null),
        ),
      ]),
    );
  }

  /// Six boxes over one hidden field: typing, deleting and pasting a whole
  /// code all work the way a single text field does.
  Widget _boxes() {
    final chars = _code.split('');
    final active = _focus.hasFocus ? math.min(chars.length, _length - 1) : -1;
    return Stack(children: [
      Row(
        children: [
          for (var i = 0; i < _length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _box(i < chars.length ? chars[i] : '', i == active)),
          ],
        ],
      ),
      Positioned.fill(
        child: Semantics(
          identifier: 'code:field',
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              // Read-only while checking, never disabled: a disabled field
              // drops the keyboard, and after a miss the code should be
              // right there to fix.
              readOnly: _busy,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              showCursor: false,
              enableInteractiveSelection: true,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _apply(),
              inputFormatters: [
                TextInputFormatter.withFunction((old, value) {
                  final clean = value.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
                  final text = clean.length > _length ? clean.substring(0, _length) : clean;
                  return TextEditingValue(
                      text: text, selection: TextSelection.collapsed(offset: text.length));
                }),
              ],
              style: const TextStyle(color: Colors.transparent),
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _box(String char, bool active) {
    final wrong = _error != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: wrong
              ? Glass.danger
              : active
                  ? Glass.ink
                  : const Color(0x14000000),
          width: active || wrong ? 1.6 : 1,
        ),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: char.isEmpty && active
          ? const _Caret()
          : Text(char,
              style: const TextStyle(
                  color: Glass.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
    );
  }

  Widget _success(CodeRedeemed done) {
    final plan = done.codePlan == 'max' ? 'Glyf Max' : 'Glyf Plus';
    final span = switch (done.days) {
      365 => 'a year',
      30 => 'a month',
      final d => '$d days',
    };
    final until = done.plan == done.codePlan ? done.expiresAt : null;
    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(children: [
        const Spacer(flex: 2),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 520),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: const KeycapGMark(size: 84),
        ),
        const SizedBox(height: 26),
        Semantics(
          identifier: 'code:done',
          child: Text('$plan is yours',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Glass.ink, fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 8),
        Text('Free for $span',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w600)),
        if (until != null) ...[
          const SizedBox(height: 4),
          Text('Until ${_date(until)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Glass.inkSoft, fontSize: 15)),
        ],
        const Spacer(flex: 3),
        PillButton(label: 'Done', onPressed: () => Navigator.of(context).pop(true)),
      ]),
    );
  }

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = d.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}

/// The blinking bar in the box that takes the next character.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) => Opacity(
        opacity: _blink.value < 0.55 ? 1 : 0,
        child: Container(width: 2, height: 26, color: Glass.ink),
      ),
    );
  }
}

/// A burst of confetti from above the middle of the screen that falls and
/// fades, once. Paper in the Glyf purple and ink with a few bright ones.
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  static const _colors = [
    Glass.accent, Glass.ink, Color(0xFFB7A6FF), Color(0xFFFFB547),
    Color(0xFF3DD9A0), Color(0xFFFF6B8B), Color(0xFF4DA3FF),
  ];

  late final AnimationController _clock = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3400))
    ..forward();
  late final List<_Paper> _papers = _make();

  List<_Paper> _make() {
    final rnd = math.Random();
    return List.generate(150, (i) {
      // Mostly up and out, a few straight up.
      final angle = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 0.95;
      final speed = 0.55 + rnd.nextDouble() * 0.75;
      return _Paper(
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        spin: (rnd.nextDouble() - 0.5) * 14,
        flip: 4 + rnd.nextDouble() * 8,
        phase: rnd.nextDouble() * math.pi * 2,
        size: 6 + rnd.nextDouble() * 6,
        color: _colors[i % _colors.length],
        shape: i % 5 == 0 ? _Shape.dot : (i % 3 == 0 ? _Shape.strip : _Shape.square),
        delay: rnd.nextDouble() * 0.12,
      );
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_papers, _clock.value)),
    );
  }
}

enum _Shape { square, strip, dot }

class _Paper {
  const _Paper({
    required this.vx, required this.vy, required this.spin, required this.flip,
    required this.phase, required this.size, required this.color, required this.shape,
    required this.delay,
  });
  final double vx, vy, spin, flip, phase, size, delay;
  final Color color;
  final _Shape shape;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.papers, this.t);
  final List<_Paper> papers;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.34);
    final reach = size.height * 1.05;
    final paint = Paint();
    for (final p in papers) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Seconds of flight: a fast burst, air drag, then gravity wins.
      final s = local * 3.2;
      final drag = (1 - math.exp(-2.2 * s)) / 2.2;
      final x = origin.dx + p.vx * reach * drag + math.sin(s * 3 + p.phase) * 10 * s;
      final y = origin.dy + p.vy * reach * drag + 0.16 * reach * s * s;
      if (y > size.height + 40) continue;
      final fade = local < 0.72 ? 1.0 : 1 - (local - 0.72) / 0.28;
      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.phase + p.spin * s);
      // A paper turning over in the air narrows and widens.
      final turn = math.cos(p.phase + p.flip * s).abs().clamp(0.15, 1.0);
      switch (p.shape) {
        case _Shape.dot:
          canvas.drawCircle(Offset.zero, p.size * 0.42, paint);
        case _Shape.strip:
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset.zero, width: p.size * 0.45, height: p.size * 1.7 * turn),
                  const Radius.circular(1.5)),
              paint);
        case _Shape.square:
          canvas.drawRect(
              Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.7 * turn), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
