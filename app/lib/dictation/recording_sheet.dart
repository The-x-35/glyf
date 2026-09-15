import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../onboarding/orb.dart';

/// §6.6 — the minimal recording sheet the keyboard hands off to.
/// Record (live on-device transcript) → Raw / Clean / Formal → Insert
/// writes the §7.2 result; the keyboard inserts it when it reappears.
class RecordingSheet extends StatefulWidget {
  const RecordingSheet({super.key, required this.intentId});
  final String intentId;

  static Future<void> open(NavigatorState navigator, String intentId) async {
    final consumed = await GlyfBridge.dictationConsume(intentId);
    if (!consumed) return; // expired or replay — refused (§7.3)
    Telemetry.log('dictation_opened');
    await navigator.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => RecordingSheet(intentId: intentId),
    ));
  }

  @override
  State<RecordingSheet> createState() => _RecordingSheetState();
}

enum _Phase { starting, recording, review, error }

class _RecordingSheetState extends State<RecordingSheet> {
  _Phase _phase = _Phase.starting;
  bool _fake = false;
  String _live = '';
  String _raw = '';
  String? _clean;
  String? _formal;
  String _mode = 'clean';
  String? _error;
  int _seconds = 0;
  Timer? _ticker;
  DateTime? _stopAt;
  int? _readyMs;

  static const _maxSeconds = 60;

  @override
  void initState() {
    super.initState();
    GlyfBridge.onDictationPartial((text) {
      if (mounted && _phase == _Phase.recording) setState(() => _live = text);
    });
    _start();
  }

  Future<void> _start() async {
    final res = await GlyfBridge.dictationStart();
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        _phase = _Phase.recording;
        _fake = res.fake;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) _stop();
      });
    } else {
      setState(() {
        _phase = _Phase.error;
        _error = res.error ?? 'Could not start recording';
      });
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _stopAt = DateTime.now();
    final stopped = await GlyfBridge.dictationStop();
    if (!mounted) return;
    final raw = stopped.trim().isEmpty ? _live.trim() : stopped.trim();
    if (raw.isEmpty) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Nothing was heard — try again closer to the mic';
      });
      return;
    }
    setState(() {
      _raw = raw;
      _phase = _Phase.review;
    });
    // §6.6: post-processing is the product. Fetch Clean immediately,
    // Formal in parallel; Raw needs nothing.
    _fetch('dictation.clean', (t) => _clean = t, isDefault: true);
    _fetch('dictation.formal', (t) => _formal = t);
  }

  Future<void> _fetch(String glyfId, void Function(String) assign,
      {bool isDefault = false}) async {
    try {
      final text = await GlyfApi.run(glyfId: glyfId, input: _raw);
      if (!mounted) return;
      setState(() {
        assign(text.trim());
        if (isDefault && _stopAt != null) {
          _readyMs = DateTime.now().difference(_stopAt!).inMilliseconds;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => assign('')); // empty = failed; UI offers Raw
    }
  }

  Future<void> _insert() async {
    final text = switch (_mode) {
      'raw' => _raw,
      'formal' => (_formal?.isNotEmpty ?? false) ? _formal! : _raw,
      _ => (_clean?.isNotEmpty ?? false) ? _clean! : _raw,
    };
    await GlyfBridge.dictationResult(widget.intentId, text, _mode);
    Telemetry.log('dictation_used', {
      'mode': _mode,
      'fake': _fake,
      'latencyMs': _readyMs ?? -1,
      'chars': text.length,
    });
    if (!mounted) return;
    // Grab the messenger BEFORE popping — the sheet's context dies with it.
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(const SnackBar(
      content: Text('Ready — switch back to where you were typing'),
      duration: Duration(seconds: 2),
    ));
  }

  void _cancel() {
    _ticker?.cancel();
    GlyfBridge.dictationCancel();
    Telemetry.log('dictation_cancelled');
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlyfBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: switch (_phase) {
              _Phase.starting => const Center(
                  child: CircularProgressIndicator(color: Glass.accent)),
              _Phase.recording => _recordingView(),
              _Phase.review => _reviewView(),
              _Phase.error => _errorView(),
            },
          ),
        ),
      ),
    );
  }

  Widget _recordingView() {
    return Column(children: [
      const SizedBox(height: 18),
      Row(children: [
        Text('Listening',
            style: TextStyle(
                color: Glass.inkSoft,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        if (_fake) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: Glass.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8)),
            child: const Text('simulated',
                style: TextStyle(color: Glass.warning, fontSize: 11)),
          ),
        ],
        const Spacer(),
        Text('0:${_seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
                color: Glass.ink, fontSize: 15, fontFeatures: [])),
      ]),
      const Spacer(),
      const _PulsingMic(),
      const SizedBox(height: 28),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 80),
        child: Text(
          _live.isEmpty ? 'Say something…' : _live,
          textAlign: TextAlign.center,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: _live.isEmpty
                  ? const Color(0xFFB6BAC3)
                  : Glass.ink,
              fontSize: 17,
              height: 1.4),
        ),
      ),
      const Spacer(),
      PillButton(label: 'Stop', onPressed: _stop),
      TextButton(
          onPressed: _cancel,
          child: Text('Cancel',
              style: TextStyle(color: Glass.inkSoft))),
      const SizedBox(height: 10),
    ]);
  }

  Widget _reviewView() {
    final current = switch (_mode) {
      'raw' => _raw,
      'clean' => _clean,
      'formal' => _formal,
      _ => _raw,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 18),
      const Text('How should it read?',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Glass.ink, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
      Row(
        children: [
          for (final (id, label) in [
            ('raw', 'Raw'),
            ('clean', 'Clean'),
            ('formal', 'Formal')
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _mode = id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _mode == id
                          ? Glass.accent
                          : const Color(0xFFF2F3F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Glass.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Expanded(
        child: GlassCard(
          child: current == null
              ? const Center(
                  child: CircularProgressIndicator(color: Glass.accent))
              : SingleChildScrollView(
                  child: Text(
                    current.isEmpty
                        ? 'Cleanup unavailable — Raw still works'
                        : current,
                    style: TextStyle(
                        color: current.isEmpty
                            ? Glass.warning
                            : Colors.white,
                        fontSize: 16,
                        height: 1.45),
                  ),
                ),
        ),
      ),
      if (_readyMs != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('clean ready in ${_readyMs}ms',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: const Color(0xFFA6ABB4), fontSize: 11)),
        ),
      const SizedBox(height: 12),
      PillButton(label: 'Insert to keyboard', onPressed: _insert),
      TextButton(
          onPressed: _cancel,
          child: Text('Discard',
              style: TextStyle(color: Glass.inkSoft))),
      const SizedBox(height: 10),
    ]);
  }

  Widget _errorView() {
    return Column(children: [
      const Spacer(),
      const Icon(Icons.mic_off, color: Glass.warning, size: 40),
      const SizedBox(height: 14),
      Text(_error ?? 'Something went wrong',
          textAlign: TextAlign.center,
          style: TextStyle(color: Glass.ink, fontSize: 16)),
      const SizedBox(height: 8),
      Text('Microphone & speech permissions live in Settings → Glyf',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Glass.inkSoft, fontSize: 13)),
      const Spacer(),
      PillButton(label: 'Open Settings', onPressed: GlyfBridge.openSettings),
      TextButton(
          onPressed: _cancel,
          child: Text('Close',
              style: TextStyle(color: Glass.inkSoft))),
      const SizedBox(height: 10),
    ]);
  }
}

class _PulsingMic extends StatefulWidget {
  const _PulsingMic();

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Stack(alignment: Alignment.center, children: [
          Container(
            width: 150 + 26 * t,
            height: 150 + 26 * t,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Glass.accent.withValues(alpha: 0.10 + 0.06 * (1 - t)),
            ),
          ),
          const GlassOrb(size: 132, floating: false),
          const Icon(Icons.mic, color: Glass.ink, size: 44),
        ]);
      },
    );
  }
}
