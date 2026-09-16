import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/catalog.dart';
import '../core/glyf_api.dart';
import '../core/recommend.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import 'demo_chat.dart';
import 'orb.dart';

/// §6.18 — onboarding, rebuilt around questions instead of tours:
/// hello → who are you → make it yours → enable → full access → your keys.
/// One screen, steps slide through an AnimatedSwitcher (no PageView, so
/// both humans and UI tests can address everything directly).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const _steps = [
    'hello', 'persona', 'feel', 'enable', 'access', 'nearby', 'keys', 'connect'
  ];
  int _step = 0;

  String? _persona;
  bool _keySounds = true;
  bool _haptics = true;
  bool _keyboardEnabled = false;
  bool _fullAccess = false;
  bool _keyboardSelected = false;
  late Map<String, String> _chosenKeys = {};
  // Google consent choices — preset from the persona, the USER decides.
  late final Set<String> _googleScopes = {};
  String? _connectNote;
  bool _locationOn = false;
  String? _locationNote;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    Telemetry.log('onboarding_step_view', {'step': _steps[_step]});
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _enableLocation() async {
    final res = await GlyfBridge.locationEnable();
    if (!mounted) return;
    setState(() {
      _locationOn = res['ok'] == true;
      _locationNote = switch (res['error']) {
        'denied' => 'Location is off for Glyf. You can enable it in Settings.',
        'nofix' => 'No recent location yet — open Maps once, then try again.',
        'unavailable' => 'Location isn\u2019t available on this device.',
        _ => null,
      };
    });
    Telemetry.log('onboarding_location', {'granted': _locationOn});
  }

  Future<void> _checkStatus() async {
    final enabled = await GlyfBridge.keyboardEnabled();
    final selected =
        Platform.isAndroid ? await GlyfBridge.keyboardSelected() : false;
    final ping = await GlyfBridge.keyboardPing();
    if (!mounted) return;
    setState(() {
      _keyboardEnabled = enabled;
      _keyboardSelected = selected;
      _fullAccess = ping?['hasFullAccess'] == true;
    });
  }

  void _advance() {
    Telemetry.log('onboarding_step_complete', {'step': _steps[_step]});
    if (_step >= _steps.length - 1) {
      _finish();
      return;
    }
    setState(() => _step++);
    if (_steps[_step] == 'keys' && _chosenKeys.isEmpty && _persona != null) {
      _chosenKeys = Map.of(Recommend.personas[_persona] ?? {});
    }
    if (_steps[_step] == 'connect' && _googleScopes.isEmpty) {
      // Persona decides the SUGGESTION; the checklist is the user's call.
      _googleScopes.addAll(switch (_persona) {
        'working' => {'calendar', 'gmail', 'meet'},
        'student' => {'calendar'},
        'creator' => {'calendar'},
        _ => {'calendar'},
      });
    }
    Telemetry.log('onboarding_step_view', {'step': _steps[_step]});
  }

  Future<void> _finish() async {
    await GlyfBridge.updateSharedSettings((s) {
      s['keyClicks'] = _keySounds;
      s['haptics'] = _haptics;
      final b = Map<String, dynamic>.from(
          (s['bindings'] as Map<String, dynamic>?) ?? {});
      b.addAll(_chosenKeys);
      s['bindings'] = b;
      return s;
    });
    await GlyfBridge.saveOnboardingState({
      'done': true,
      'persona': _persona,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
    Telemetry.log('onboarding_complete',
        {'persona': _persona ?? 'none', 'keys': _chosenKeys.length});
    if (!mounted) {
      widget.onDone();
      return;
    }
    // Settings are done; now the part that actually teaches Glyf — the
    // website's guided chat, played on the keyboard they just enabled.
    // Skippable from its own header.
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => DemoChat(onDone: () => Navigator.of(ctx).pop()),
    ));
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlyfBackground(
        child: SafeArea(
          child: Column(children: [
            _progress(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0.06, 0),
                            end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _buildStep(),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _progress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Row(
        children: List.generate(_steps.length, (i) {
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i <= _step ? Glass.ink : const Color(0xFFE3E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep() {
    switch (_steps[_step]) {
      case 'hello':
        return _frame(children: [
          const Spacer(),
          const Center(child: GlassOrb(size: 150, label: 'g')),
          const SizedBox(height: 30),
          const Center(child: GlyfWordmark(size: 44)),
          const SizedBox(height: 10),
          const Center(
            child: Text('Every key is a Glyf.',
                style: TextStyle(color: Glass.inkSoft, fontSize: 15)),
          ),
          const Spacer(),
          _pill('Set up Glyf', onTap: _advance),
          const SizedBox(height: 20),
        ]);

      case 'persona':
        return _frame(children: [
          const SizedBox(height: 30),
          _headline('What fills your day?', 'Your keys get picked around it.'),
          const SizedBox(height: 20),
          for (final (id, emoji, label) in const [
            ('student', '🎓', 'Studying'),
            ('working', '💼', 'Working'),
            ('creator', '📣', 'Creating content'),
            ('texting', '💬', 'Mostly texting'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                identifier: 'onb:persona:$id',
                button: true,
                child: GlassCard(
                  borderColor: _persona == id ? Glass.accent : null,
                  onTap: () => setState(() => _persona = id),
                  child: Row(children: [
                    Text(emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: Glass.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (_persona == id)
                      const Icon(Icons.check_circle,
                          color: Glass.accent, size: 20),
                  ]),
                ),
              ),
            ),
          const Spacer(),
          _pill('Continue', onTap: _persona == null ? null : _advance),
          _skip(),
        ]);

      case 'feel':
        return _frame(children: [
          const SizedBox(height: 30),
          _headline('Make it yours', 'Both change anytime in Profile.'),
          const SizedBox(height: 20),
          _toggleCard('🔊', 'Key sounds', _keySounds,
              (v) => setState(() => _keySounds = v)),
          const SizedBox(height: 10),
          _toggleCard('📳', 'Haptics', _haptics,
              (v) => setState(() => _haptics = v)),
          const Spacer(),
          _pill('Continue', onTap: _advance),
          const SizedBox(height: 20),
        ]);

      case 'enable':
        return _frame(children: [
          const SizedBox(height: 30),
          _headline(
              'Turn Glyf on',
              Platform.isAndroid
                  ? 'Settings → On-screen keyboard → Glyf'
                  : 'Settings → General → Keyboard → Keyboards'),
          const SizedBox(height: 26),
          Center(
            child: AnimatedScale(
              scale: _keyboardEnabled ? 1 : 0.92,
              duration: const Duration(milliseconds: 300),
              child: Icon(Icons.check_circle,
                  size: 74,
                  color: _keyboardEnabled
                      ? Glass.success
                      : const Color(0xFFDDE0E6)),
            ),
          ),
          const Spacer(),
          if (!_keyboardEnabled)
            _pill('Open Settings', onTap: () => GlyfBridge.openSettings()),
          if (_keyboardEnabled) _pill('Continue', onTap: _advance),
          if (!_keyboardEnabled) _skip(),
          if (_keyboardEnabled) const SizedBox(height: 20),
        ]);

      case 'access':
        final step2Done = Platform.isAndroid ? _keyboardSelected : _fullAccess;
        return _frame(children: [
          const SizedBox(height: 30),
          Platform.isAndroid
              ? _headline('Switch to Glyf',
                  'Pick Glyf from the keyboard list.')
              : _headline('Allow Full Access',
                  'AI runs need it. Typing works without it.'),
          const SizedBox(height: 26),
          Center(
            child: AnimatedScale(
              scale: step2Done ? 1 : 0.92,
              duration: const Duration(milliseconds: 300),
              child: Icon(Icons.check_circle,
                  size: 74,
                  color: step2Done ? Glass.success : const Color(0xFFDDE0E6)),
            ),
          ),
          const Spacer(),
          if (!step2Done)
            _pill(Platform.isAndroid ? 'Choose keyboard' : 'Open Settings',
                onTap: () => Platform.isAndroid
                    ? GlyfBridge.showImePicker()
                    : GlyfBridge.openSettings()),
          if (step2Done) _pill('Continue', onTap: _advance),
          if (!step2Done) _skip(),
          if (step2Done) const SizedBox(height: 20),
        ]);

      // "Coffee near me" is only a real answer if the keyboard knows roughly
      // where you are. The APP asks — a keyboard extension cannot — and caches
      // a coarse fix for the search suite to send.
      case 'nearby':
        return _frame(children: [
          const SizedBox(height: 30),
          _headline('Search what\u2019s near you',
              'So “coffee near me” finds coffee near you.'),
          const SizedBox(height: 26),
          Center(
            child: AnimatedScale(
              scale: _locationOn ? 1 : 0.92,
              duration: const Duration(milliseconds: 300),
              child: Icon(Icons.near_me_rounded,
                  size: 74,
                  color: _locationOn ? Glass.success : const Color(0xFFDDE0E6)),
            ),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Approximate only, kept on your device, and never stored on our '
              'servers. You can turn it off any time in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Glass.inkSoft, fontSize: 12.5, height: 1.4),
            ),
          ),
          if (_locationNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_locationNote!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
            ),
          const Spacer(),
          if (_locationOn)
            _pill('Continue', onTap: _advance)
          else
            _pill('Turn on nearby search', onTap: _enableLocation),
          if (!_locationOn) _skip(label: 'Not now'),
          if (_locationOn) const SizedBox(height: 20),
        ]);

      case 'connect':
        return _frame(children: [
          const SizedBox(height: 30),
          _headline('Connect your Google',
              'You choose exactly what Glyf can reach.'),
          const SizedBox(height: 20),
          for (final (id, emoji, label, detail) in const [
            ('youtube', '▶️', 'YouTube', 'Your liked videos in the search tab'),
            ('calendar', '📅', 'Calendar', 'Drop events into your text'),
            ('gmail', '✉️', 'Gmail', 'Draft replies where you type'),
            ('meet', '🎥', 'Meet', 'Create meeting links inline'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                onTap: () => setState(() {
                  if (!_googleScopes.remove(id)) _googleScopes.add(id);
                }),
                child: Row(children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  color: Glass.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          Text(detail,
                              style: const TextStyle(
                                  color: Glass.inkSoft, fontSize: 12)),
                        ]),
                  ),
                  Icon(
                      _googleScopes.contains(id)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 22,
                      color: _googleScopes.contains(id)
                          ? Glass.accent
                          : const Color(0xFFD3D6DD)),
                ]),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              'Read-only, and only what you tick. Glyf never sees your Google '
              'password, and signing in does not give it your search history.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Glass.inkSoft, fontSize: 12, height: 1.4),
            ),
          ),
          if (_connectNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_connectNote!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
            ),
          const Spacer(),
          _pill('Sign in with Google', onTap: _connectGoogle),
          _skip(label: 'Not now'),
        ]);

      case 'keys':
        final recs = _persona == null
            ? Recommend.personas['texting']!
            : (Recommend.personas[_persona] ?? {});
        return _frame(children: [
          const SizedBox(height: 30),
          _headline('Your starting keys',
              'Hold a key to fire it. Change any of this later.'),
          const SizedBox(height: 20),
          for (final e in recs.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                onTap: () => setState(() {
                  if (_chosenKeys.containsKey(e.key)) {
                    _chosenKeys.remove(e.key);
                  } else {
                    _chosenKeys[e.key] = e.value;
                  }
                }),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Glass.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(e.key.toUpperCase(),
                        style: const TextStyle(
                            color: Glass.ink,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(Catalog.byId(e.value).title,
                        style: const TextStyle(
                            color: Glass.ink,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  Icon(
                      _chosenKeys.containsKey(e.key)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 22,
                      color: _chosenKeys.containsKey(e.key)
                          ? Glass.accent
                          : const Color(0xFFD3D6DD)),
                ]),
              ),
            ),
          const Spacer(),
          _pill('Continue', onTap: _advance),
          const SizedBox(height: 20),
        ]);

      default:
        return const SizedBox.shrink();
    }
  }

  /// Opens Google's consent screen with the chosen scopes; onboarding
  /// finishes either way — the connection lands via the glyf:// deep link.
  Future<void> _connectGoogle() async {
    Telemetry.log('onboarding_google_start',
        {'scopes': _googleScopes.join(',')});
    try {
      final url = await GlyfApi.googleStartUrl(_googleScopes.toList());
      await GlyfBridge.openURL(url);
      _advance(); // finish; the callback deep-links back into the app
    } on GlyfApiException catch (e) {
      setState(() => _connectNote = e.message);
    } catch (_) {
      setState(() => _connectNote = 'Engine offline — connect later from Profile');
    }
  }

  // ── pieces ──────────────────────────────────────────────────────────────

  Widget _frame({required List<Widget> children}) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children),
      );

  Widget _headline(String title, String sub) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: Glass.ink, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(sub, style: const TextStyle(color: Glass.inkSoft, fontSize: 14)),
      ]);

  Widget _pill(String label, {VoidCallback? onTap}) => Semantics(
        identifier: 'onb:next',
        button: true,
        child: PillButton(label: label, onPressed: onTap),
      );

  Widget _skip({String label = 'Skip'}) => Semantics(
        identifier: 'onb:skip',
        button: true,
        child: TextButton(
          onPressed: _advance,
          child: Text(label,
              style: const TextStyle(color: Glass.inkSoft, fontSize: 14)),
        ),
      );

  Widget _toggleCard(
      String emoji, String label, bool value, ValueChanged<bool> onChanged) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 13),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: Glass.ink,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700)),
        ),
        CupertinoSwitch(
            value: value, activeTrackColor: Glass.ink, onChanged: onChanged),
      ]),
    );
  }
}
