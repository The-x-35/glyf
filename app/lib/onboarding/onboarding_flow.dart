import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import 'demo_chat.dart';
import '../profile/brand_marks.dart';
import 'talking_orb.dart';

/// Onboarding: sign in, meet the orb, tell it what to remember, make the
/// keyboard yours, turn it on, then the website's chats on the real keyboard.
/// One screen, steps slide through an AnimatedSwitcher (no PageView, so
/// both humans and UI tests can address everything directly).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  /// 'connect' only when this server can actually sign in with Google.
  List<String> _steps = const [
    'signin', 'meet', 'details', 'feel', 'enable', 'access', 'nearby', 'connect'
  ];
  int _step = 0;

  String? _persona;
  /// The details that make everything else one tap: a form asking for an
  /// email gets the email, "my address is" gets the address. They are saved
  /// in the on-device vault, never uploaded.
  static const _detailFields = <(String, String, String)>[
    ('name', 'Name', 'Your name'),
    ('email', 'Email', 'you@example.com'),
    ('phone', 'Phone', '+91 98765 43210'),
    ('address', 'Home', 'Flat, street, city, pin'),
    ('upi', 'UPI', 'you@okbank'),
  ];
  final Map<String, TextEditingController> _details = {
    for (final f in _detailFields) f.$1: TextEditingController(),
  };
  String? _detailsError;
  bool _keySounds = true;
  bool _haptics = true;
  /// On by default, like Gboard: what you copy is there to paste later.
  bool _clipboard = true;
  /// On by default, like Gboard; photo access is asked for on Continue.
  bool _screenshots = true;
  bool _keyboardEnabled = false;
  bool _fullAccess = false;
  bool _keyboardSelected = false;
  // Google consent choices — preset from the persona, the USER decides.
  late final Set<String> _googleScopes = {};
  String? _connectNote;
  bool _locationOn = false;
  String? _locationNote;
  Timer? _poll;

  // Sign-in
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _emailOpen = false;
  bool _codeSent = false;
  bool _busy = false;
  String? _signInError;
  bool _meetDone = false;

  @override
  void initState() {
    super.initState();
    // Already signed in (onboarding was left half way): start after sign-in.
    if (Auth.signedIn) _step = 1;
    Telemetry.log('onboarding_step_view', {'step': _steps[_step]});
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _checkStatus());
    _dropConnectIfUnavailable();
  }

  /// A Google step that can only fail is worse than none: ask the server
  /// whether sign-in is set up, and leave the step out when it is not.
  Future<void> _dropConnectIfUnavailable() async {
    bool configured = false;
    try {
      final status = await GlyfApi.connectorsStatus();
      final providers = (status['providers'] as List?) ?? const [];
      configured = providers.any((p) => p is Map && p['id'] == 'google' && p['configured'] == true);
    } catch (_) {
      configured = false;
    }
    if (!mounted || configured) return;
    setState(() => _steps = _steps.where((s) => s != 'connect').toList());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _email.dispose();
    _code.dispose();
    for (final c in _details.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Saves whatever was filled in; empty boxes are simply skipped.
  Future<void> _saveDetails() async {
    String? firstError;
    var saved = 0;
    for (final (kind, label, _) in _detailFields) {
      final value = _details[kind]!.text.trim();
      if (value.isEmpty) continue;
      final res = await GlyfBridge.vaultUpsertField(
          kind: kind, label: label, value: value);
      if (res.ok) {
        saved++;
      } else {
        firstError ??= res.error;
      }
    }
    Telemetry.log('onboarding_details', {'saved': saved});
    if (!mounted) return;
    if (firstError != null) {
      setState(() => _detailsError = firstError);
      return;
    }
    setState(() => _detailsError = null);
    _advance();
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
    if (_steps[_step] == 'details') _prefillFromAccount();
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

  /// The name and email the account came with, so nobody types them twice.
  void _prefillFromAccount() {
    final id = Auth.identity();
    if (_details['name']!.text.isEmpty && (id.name ?? '').isNotEmpty) _details['name']!.text = id.name!;
    if (_details['email']!.text.isEmpty && (id.email ?? '').isNotEmpty) _details['email']!.text = id.email!;
  }

  Future<void> _signedIn(String? error) async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _signInError = error;
    });
    if (error == null && Auth.signedIn) {
      Telemetry.log('onboarding_signed_in', {});
      _advance();
    }
  }

  Future<void> _google() async {
    setState(() { _busy = true; _signInError = null; });
    _signedIn(await Auth.signInWithGoogle());
  }

  Future<void> _apple() async {
    setState(() { _busy = true; _signInError = null; });
    _signedIn(await Auth.signInWithApple());
  }

  Future<void> _emailContinue() async {
    final email = _email.text.trim();
    if (!_codeSent) {
      if (!email.contains('@') || !email.contains('.')) {
        setState(() => _signInError = 'Enter your email address.');
        return;
      }
      setState(() { _busy = true; _signInError = null; });
      final error = await Auth.sendEmailCode(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _signInError = error;
        _codeSent = error == null;
      });
      return;
    }
    if (_code.text.trim().length < 6) {
      setState(() => _signInError = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() { _busy = true; _signInError = null; });
    _signedIn(await Auth.verifyEmailCode(email, _code.text));
  }

  /// Photo access for recent screenshots, asked when it is on and they move on.
  Future<void> _feelContinue() async {
    if (_screenshots && !await GlyfBridge.screenshotAccess()) {
      if (mounted) setState(() => _screenshots = false);
    }
    _advance();
  }

  Future<void> _finish() async {
    await GlyfBridge.updateSharedSettings((s) {
      s['keyClicks'] = _keySounds;
      s['haptics'] = _haptics;
      s['clipboardHistory'] = _clipboard;
      s['clipboardScreenshots'] = _screenshots;
      return s;
    });
    await GlyfBridge.saveOnboardingState({
      'done': true,
      'persona': _persona,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
    Telemetry.log('onboarding_complete', {'persona': _persona ?? 'none'});
    unawaited(Auth.syncPrefs());
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
            if (_steps[_step] != 'signin') _progress(),
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
      case 'signin':
        return _frame(children: [
          const Spacer(flex: 4),
          if (!_emailOpen)
            const Center(
              child: TalkingOrb(
                size: 170,
                titleSize: 34,
                lines: ['Hi, I’m {glyf}', 'Sign in to set up your keyboard.'],
              ),
            )
          else
            const Center(
              child: TalkingOrb(size: 96, titleSize: 26, lines: ['Your email']),
            ),
          const Spacer(flex: 3),
          if (!_emailOpen) ...[
            if (Platform.isIOS) ...[
              _authButton(
                id: 'onb:apple',
                label: 'Continue with Apple',
                icon: const Icon(Icons.apple, color: Colors.white, size: 24),
                dark: true,
                onTap: _busy ? null : _apple,
              ),
              const SizedBox(height: 12),
            ],
            _authButton(
              id: 'onb:google',
              label: 'Continue with Google',
              icon: const GoogleG(size: 20),
              onTap: _busy ? null : _google,
            ),
            const SizedBox(height: 12),
            _authButton(
              id: 'onb:email',
              label: 'Continue with email',
              icon: const Icon(Icons.mail_outline_rounded, color: Glass.ink, size: 22),
              onTap: _busy ? null : () => setState(() { _emailOpen = true; _signInError = null; }),
            ),
          ] else ...[
            GlassCard(
              child: Semantics(
                identifier: 'onb:email-field',
                child: TextField(
                  controller: _email,
                  enabled: !_codeSent,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    isDense: true, border: InputBorder.none, hintText: 'you@email.com',
                    hintStyle: TextStyle(color: Glass.inkSoft)),
                  onSubmitted: (_) => _emailContinue(),
                ),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 10),
              GlassCard(
                child: Semantics(
                  identifier: 'onb:code-field',
                  child: TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      isDense: true, border: InputBorder.none, counterText: '', hintText: '6-digit code',
                      hintStyle: TextStyle(color: Glass.inkSoft, fontSize: 16, letterSpacing: 0, fontWeight: FontWeight.w400)),
                    onSubmitted: (_) => _emailContinue(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _pill(_busy ? 'One moment…' : (_codeSent ? 'Sign in' : 'Send code'),
                onTap: _busy ? null : _emailContinue),
            TextButton(
              onPressed: _busy ? null : () => setState(() {
                _emailOpen = false;
                _codeSent = false;
                _code.clear();
                _signInError = null;
              }),
              child: const Text('Other ways to sign in', style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
            ),
          ],
          if (_signInError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_signInError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: Glass.danger)),
            ),
          const SizedBox(height: 18),
        ]);

      case 'meet':
        return _frame(children: [
          const SizedBox(height: 18),
          Center(
            child: TalkingOrb(
              size: 116,
              titleSize: 28,
              lines: const [
                'Let me remember you.',
                'When someone asks for your address or UPI, it’s one tap.',
              ],
              onDone: () { if (mounted) setState(() => _meetDone = true); },
            ),
          ),
          const SizedBox(height: 22),
          const RememberDemo(),
          const Spacer(),
          AnimatedOpacity(
            opacity: _meetDone ? 1 : 0.35,
            duration: const Duration(milliseconds: 300),
            child: _pill('Tell Glyf about me', onTap: _advance),
          ),
          const SizedBox(height: 20),
        ]);

      case 'details':
        return _frame(children: [
          const SizedBox(height: 10),
          const Center(child: TalkingOrb(size: 76, titleSize: 26, lines: ['What should I remember?'])),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              for (final (kind, label, hint) in _detailFields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    child: Row(children: [
                      SizedBox(
                        width: 74,
                        child: Text(label,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: Semantics(
                          identifier: 'onb:detail:$kind',
                          child: TextField(
                            controller: _details[kind],
                            keyboardType: switch (kind) {
                              'email' => TextInputType.emailAddress,
                              'phone' => TextInputType.phone,
                              'address' => TextInputType.streetAddress,
                              _ => TextInputType.text,
                            },
                            textCapitalization: kind == 'name'
                                ? TextCapitalization.words
                                : TextCapitalization.none,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: hint,
                              hintStyle: const TextStyle(color: Glass.inkSoft),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              if (_detailsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Text(_detailsError!,
                      style: const TextStyle(fontSize: 13, color: Glass.danger)),
                ),
            ]),
          ),
          _pill('Save', onTap: _saveDetails),
          _skip(),
        ]);

      case 'feel':
        return _frame(children: [
          const SizedBox(height: 30),
          _headline('Make it yours'),
          const SizedBox(height: 20),
          _toggleCard('🔊', 'Key sounds', _keySounds,
              (v) => setState(() => _keySounds = v)),
          const SizedBox(height: 10),
          _toggleCard('📳', 'Haptics', _haptics,
              (v) => setState(() => _haptics = v)),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Clipboard',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
          ),
          _toggleCard('📋', 'Keep what you copy', _clipboard,
              (v) => setState(() => _clipboard = v)),
          const SizedBox(height: 10),
          _toggleCard('🖼️', 'Recent screenshots', _screenshots,
              (v) => setState(() => _screenshots = v)),
          const Spacer(),
          _pill('Continue', onTap: _feelContinue),
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
              : _headline('Allow Full Access'),
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
          _headline('Search what\u2019s near you'),
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
          _headline('Connect your Google'),
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

  Widget _headline(String title, [String? sub]) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: Glass.ink, fontSize: 26, fontWeight: FontWeight.w800)),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(sub, style: const TextStyle(color: Glass.inkSoft, fontSize: 14)),
        ],
      ]);

  Widget _pill(String label, {VoidCallback? onTap}) => Semantics(
        identifier: 'onb:next',
        button: true,
        child: PillButton(label: label, onPressed: onTap),
      );

  Widget _authButton({
    required String id,
    required String label,
    required Widget icon,
    required VoidCallback? onTap,
    bool dark = false,
  }) =>
      Semantics(
        identifier: id,
        button: true,
        // Equal weight for every way in (Google's and Apple's guidelines):
        // same height, same shape, the logo in a fixed slot on the left and
        // the words centred.
        child: SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              backgroundColor: dark ? Colors.black : Colors.white,
              foregroundColor: dark ? Colors.white : const Color(0xFF1F1F1F),
              disabledBackgroundColor: dark ? Colors.black : Colors.white,
              side: BorderSide(color: dark ? Colors.black : const Color(0xFF747775), width: dark ? 0 : 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2),
            ),
            child: Stack(alignment: Alignment.center, children: [
              Align(alignment: Alignment.centerLeft, child: SizedBox(width: 26, height: 26, child: Center(child: icon))),
              Text(label),
            ]),
          ),
        ),
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
