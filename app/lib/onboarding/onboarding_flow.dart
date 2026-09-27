import 'dart:async';
import 'dart:convert';
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
import 'setup_hero.dart';
import 'talking_orb.dart';
import 'tour_preview.dart';
import 'tour_scenarios.dart';

/// Onboarding: sign in with Apple or Google, meet the orb, tell it what to
/// remember, make the keyboard yours, turn it on, nearby search, the
/// calendar (the phone's, and Google Calendar and Meet when sign-in didn't
/// bring them: these are asked here and nowhere else), then an offer to see
/// the website's chats played on the real keyboard (or skip straight to home).
/// One screen, steps slide through an AnimatedSwitcher (no PageView, so
/// both humans and UI tests can address everything directly).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone, this.resume = const {}});

  /// What a previous run had saved when the app ended (its step and the
  /// persona picked): iOS kills the app the moment Full Access is granted
  /// in Settings, so coming back must land there, not on the hello.
  final Map<String, dynamic> resume;
  final VoidCallback onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  /// 'connect' only when this server can actually sign in with Google.
  // 'connect' (Google calendar/mail) is out of the flow until the connector
  // works end to end; it stays reachable from Profile › Connected tools.
  List<String> _steps = const [
    'signin', 'meet', 'details', 'feel', 'setup', 'nearby', 'calendar', 'tour'
  ];
  int _step = 0;

  /// Which way the last step change went, for the slide.
  bool _forward = true;

  /// Steps already seen: coming back to one, its orb doesn't talk again.
  final Set<String> _heard = {};

  /// Saving settings and "onboarding done" as the tour offer opens.
  Future<void>? _completing;

  /// The tour was opened or skipped: a second tap does nothing.
  bool _leaving = false;

  String? _persona;
  /// The details that make everything else one tap: a form asking for an
  /// email gets the email, "my address is" gets the address, "my wallet
  /// address is" the Solana address. They are saved in the on-device vault,
  /// never uploaded. (id, kind, label, hint): X and Telegram are both socials.
  static const _detailFields = <(String, String, String, String)>[
    ('name', 'name', 'Name', 'Your name'),
    ('email', 'email', 'Email', 'you@example.com'),
    ('phone', 'phone', 'Phone', '+1 415 555 0132'),
    ('address', 'address', 'Home', 'Street, city, postcode'),
    ('wallet', 'wallet', 'Wallet address', 'Your Solana address'),
    ('x', 'social', 'X', 'x.com/you'),
    ('telegram', 'social', 'Telegram', 't.me/you'),
  ];
  final Map<String, TextEditingController> _details = {
    for (final f in _detailFields) f.$1: TextEditingController(),
  };
  final Map<String, FocusNode> _detailFocus = {
    for (final f in _detailFields) f.$1: FocusNode(),
  };
  String? _detailsError;
  /// Why the screenshots switch wouldn't stay on, when it wouldn't.
  String? _photosNote;
  /// When this run of the setup step began: only what the keyboard says
  /// after this counts as proof of Full Access.
  DateTime? _setupSince;
  /// The box the keyboard is asked to turn up in.
  final _try = TextEditingController();
  final _tryFocus = FocusNode();
  bool _keySounds = true;
  bool _haptics = true;
  /// On by default, like Gboard: what you copy is there to paste later.
  bool _clipboard = true;
  /// Off until asked for: turning it on is what asks for the photo library.
  bool _screenshots = true;
  bool _keyboardEnabled = false;
  bool _fullAccess = false;
  bool _keyboardSelected = false;
  // Google consent choices — preset from the persona, the USER decides.
  late final Set<String> _googleScopes = {};
  String? _connectNote;
  bool _locationOn = false;
  String? _locationNote;
  /// The calendar step: the phone's calendar for the keyboard, and Google
  /// Meet (Google Calendar and Meet) when sign-in didn't bring it.
  bool _calendarOn = false;
  bool _calendarAsked = false;
  bool _meetOn = false;
  String? _calendarNote;
  Timer? _poll;

  // Sign-in
  bool _busy = false;
  String? _signInError;
  bool _meetDone = false;

  /// The step on screen when the app opened: the launch bubble lands on its orb.
  late final int _launchStep;

  @override
  void initState() {
    super.initState();
    // Already signed in (onboarding was left half way): start after sign-in.
    if (Auth.signedIn) _step = 1;
    // …and where it was left, when that is known: granting Full Access ends
    // the app (tccd: "access to kTCCServiceKeyboardNetwork changed"), so
    // the setup step in particular must survive a relaunch.
    final resume = widget.resume['step'] as String?;
    final at = resume == null ? -1 : _steps.indexOf(resume);
    if (Auth.signedIn && at > 1 && resume != 'tour') {
      _step = at;
      _heard.addAll(_steps.take(at));
      _persona ??= widget.resume['persona'] as String?;
      // Choices made on the way here were saved as they were made.
      if (at > _steps.indexOf('feel')) unawaited(_loadFeel());
      if (resume == 'nearby') unawaited(_loadLocation());
      if (resume == 'calendar') unawaited(_loadCalendarStep());
      if (resume == 'details') _prefillFromAccount();
      if (resume == 'setup') {
        _setupSince = DateTime.now().toUtc();
        // Ask the keyboard to turn up and say whether it has Full Access
        // now, instead of leaving the person to find the box.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_fullAccess) _tryFocus.requestFocus();
        });
      }
    }
    _launchStep = _step;
    for (final c in _details.values) {
      c.addListener(_detailsChanged);
    }
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
    // Keep the step on screen by name: a resumed run may already be past
    // the point where the list loses an entry.
    final name = _steps[_step];
    setState(() {
      _steps = _steps.where((s) => s != 'connect').toList();
      _step = _steps.indexOf(name == 'connect' ? 'tour' : name);
    });
    if (_steps[_step] == 'tour') _completing ??= _complete();
  }

  /// Where we are, for a relaunch. Sign-in has nothing to come back to and
  /// the tour offer writes "done" itself.
  void _remember() {
    final name = _steps[_step];
    if (name == 'signin' || name == 'tour') return;
    unawaited(GlyfBridge.saveOnboardingState({'step': name, if (_persona != null) 'persona': _persona}));
  }

  /// The "Make it yours" switches, kept in shared settings the moment that
  /// step is left — so a relaunch keeps them, and the keyboard sees them.
  Future<void> _saveFeel() => GlyfBridge.updateSharedSettings((s) {
        s['keyClicks'] = _keySounds;
        s['haptics'] = _haptics;
        s['clipboardHistory'] = _clipboard;
        s['clipboardScreenshots'] = _screenshots;
        return s;
      });

  Future<void> _loadFeel() async {
    final s = await GlyfBridge.sharedSettings();
    if (!mounted) return;
    setState(() {
      _keySounds = s['keyClicks'] as bool? ?? _keySounds;
      _haptics = s['haptics'] as bool? ?? _haptics;
      _clipboard = s['clipboardHistory'] as bool? ?? _clipboard;
      _screenshots = s['clipboardScreenshots'] as bool? ?? _screenshots;
    });
  }

  /// Nearby search an earlier run already turned on stays on.
  Future<void> _loadLocation() async {
    final status = await GlyfBridge.locationStatus();
    if (!mounted) return;
    setState(() => _locationOn = status['enabled'] == true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in _details.values) {
      c.dispose();
    }
    for (final f in _detailFocus.values) {
      f.dispose();
    }
    _try.dispose();
    _tryFocus.dispose();
    super.dispose();
  }

  void _detailsChanged() {
    if (mounted && _steps[_step] == 'details') setState(() {});
  }

  int get _filledDetails =>
      _detailFields.where((f) => _details[f.$1]!.text.trim().isNotEmpty).length;

  /// Saves whatever was filled in; empty boxes are simply skipped. Coming
  /// back and saving again updates what was saved, never adds a twin.
  Future<void> _saveDetails() async {
    FocusScope.of(context).unfocus();
    final saved0 = <String, Map>{};
    try {
      final raw = await GlyfBridge.vaultList();
      final fields = raw == null ? const [] : ((jsonDecode(raw) as Map)['fields'] as List? ?? const []);
      for (final f in fields.whereType<Map>()) {
        saved0.putIfAbsent('${f['kind']}|${f['label']}', () => f);
      }
    } catch (_) {}
    String? firstError;
    var saved = 0;
    for (final (id, kind, label, _) in _detailFields) {
      final value = _details[id]!.text.trim();
      if (value.isEmpty) continue;
      final prior = saved0['$kind|$label'];
      if (prior != null && prior['value'] == value) {
        saved++;
        continue;
      }
      final res = await GlyfBridge.vaultUpsertField(
          id: prior?['id'] as String?, kind: kind, label: label, value: value);
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
        'nofix' => 'No recent location yet. Open Maps once, then try again.',
        'unavailable' => 'Location isn\u2019t available on this device.',
        _ => null,
      };
    });
    Telemetry.log('onboarding_location', {'granted': _locationOn});
  }

  /// What the calendar step starts from: a Google sign-in may have brought
  /// Google Calendar and Meet already.
  Future<void> _loadCalendarStep() async {
    final cal = await GlyfBridge.calendarStatus();
    final google = await GlyfBridge.googleStatus();
    if (!mounted) return;
    setState(() {
      _calendarOn = cal['enabled'] == true;
      _meetOn = google['meet'] == true;
    });
  }

  Future<void> _enableCalendar() async {
    final res = await GlyfBridge.calendarEnable();
    if (!mounted) return;
    setState(() {
      _calendarAsked = true;
      _calendarOn = res['ok'] == true;
      _calendarNote = _calendarOn ? null : 'Calendar is off for Glyf. You can allow it in Settings.';
    });
    Telemetry.log('onboarding_calendar', {'granted': _calendarOn});
  }

  Future<void> _connectMeet() async {
    setState(() => _busy = true);
    final error = await Auth.connectGoogle();
    final google = await GlyfBridge.googleStatus();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _meetOn = google['meet'] == true;
      _calendarNote = error;
    });
    Telemetry.log('onboarding_google_meet', {'granted': _meetOn});
  }

  /// Where the keyboard gets to speak for itself: type one letter with Glyf
  /// and it reports Full Access, which nothing else on the phone can tell us.
  Widget _tryHere() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          identifier: 'onb:setup:try',
          child: TextField(
            controller: _try,
            focusNode: _tryFocus,
            autocorrect: false,
            style: const TextStyle(color: Glass.ink, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Type a letter here',
              hintStyle: const TextStyle(color: Glass.inkSoft, fontSize: 15),
              prefixIcon: const Icon(Icons.keyboard_alt_outlined, size: 20, color: Glass.inkSoft),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8, left: 4),
          child: Text('Tap 🌐 on the keyboard and pick Glyf',
              style: TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
        ),
      ]);

  /// Takes them where the thing they tapped is turned on.
  void _openSetup(String what) {
    Telemetry.log('onboarding_setup_open', {'what': what});
    if (what == 'picker') {
      GlyfBridge.showImePicker();
    } else {
      GlyfBridge.openSettings();
    }
  }

  Future<void> _checkStatus() async {
    final enabled = await GlyfBridge.keyboardEnabled();
    final selected =
        Platform.isAndroid ? await GlyfBridge.keyboardSelected() : false;
    final ping = await GlyfBridge.keyboardPing();
    if (!mounted) return;
    // The keyboard reports Full Access by running, and what it said last
    // week means nothing now — a keyboard that has been turned off can't
    // even correct it. So only a report from this visit counts, and only
    // while the keyboard is on.
    final said = DateTime.tryParse('${ping?['ts'] ?? ''}');
    final fresh = said != null && _setupSince != null && said.isAfter(_setupSince!);
    final hadAccess = _fullAccess;
    setState(() {
      _keyboardEnabled = enabled;
      _keyboardSelected = selected;
      _fullAccess = enabled && fresh && ping?['hasFullAccess'] == true;
    });
    // The keyboard came up to say so. Now that it has, it can go, and the
    // Continue it was covering comes back.
    if (!hadAccess && _fullAccess && _tryFocus.hasFocus) _tryFocus.unfocus();
  }

  void _advance() {
    Telemetry.log('onboarding_step_complete', {'step': _steps[_step]});
    // The tour offer is the end: its own buttons leave onboarding.
    if (_step >= _steps.length - 1) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final leaving = _steps[_step];
    _heard.add(leaving);
    setState(() {
      _forward = true;
      _step++;
    });
    _remember();
    if (leaving == 'feel') unawaited(_saveFeel());
    if (_steps[_step] == 'details') _prefillFromAccount();
    if (_steps[_step] == 'setup') _setupSince = DateTime.now().toUtc();
    if (_steps[_step] == 'calendar') unawaited(_loadCalendarStep());
    if (_steps[_step] == 'tour') _completing ??= _complete();
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

  /// Back is there once signed in and past the orb's hello, up to the tour
  /// offer (by then onboarding is saved as done).
  bool get _canGoBack {
    final name = _steps[_step];
    return _step > _steps.indexOf('meet') && name != 'tour' && !_busy;
  }

  void _back() {
    if (!_canGoBack) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _heard.add(_steps[_step]);
    setState(() {
      _forward = false;
      _step--;
    });
    _remember();
    if (_steps[_step] == 'setup') _setupSince = DateTime.now().toUtc();
    Telemetry.log('onboarding_step_back', {'step': _steps[_step]});
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
      // Signed out and back in on a phone that's already set up: home.
      final state = await GlyfBridge.onboardingState();
      if (!mounted) return;
      if (state['done'] == true) {
        widget.onDone();
        return;
      }
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

  /// Three quick taps on the orb open App Review's sign-in (the review
  /// notes in App Store Connect say so): Glyf has no email-and-password
  /// accounts of its own to hand Apple, so the reviewer gets this door.
  int _reviewTaps = 0;
  DateTime _reviewTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _reviewTap() {
    final now = DateTime.now();
    _reviewTaps = now.difference(_reviewTapAt) < const Duration(seconds: 2) ? _reviewTaps + 1 : 1;
    _reviewTapAt = now;
    if (_reviewTaps >= 3) {
      _reviewTaps = 0;
      _showReviewSignIn();
    }
  }

  Future<void> _showReviewSignIn() async {
    final controller = TextEditingController();
    String? error;
    var busy = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Glass.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 22, 24, MediaQuery.viewInsetsOf(sheetCtx).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('App Review sign-in',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Glass.ink)),
              const SizedBox(height: 6),
              const Text('The password from App Store Connect.',
                  style: TextStyle(fontSize: 13.5, color: Glass.inkSoft)),
              const SizedBox(height: 14),
              TextField(
                key: const Key('onb:review-password'),
                controller: controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 15, color: Glass.ink),
                decoration: InputDecoration(
                  hintText: 'Reviewer password',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Glass.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Glass.hairline),
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13.5, color: Glass.danger)),
                ),
              const SizedBox(height: 14),
              busy
                  ? const SizedBox(
                      height: 52,
                      child: Center(
                        child: SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink),
                        ),
                      ),
                    )
                  : PillButton(
                      label: 'Sign in',
                      onPressed: () async {
                        setSheet(() { busy = true; error = null; });
                        final e = await Auth.signInForReview(controller.text);
                        if (!sheetCtx.mounted) return;
                        if (e != null) {
                          setSheet(() { busy = false; error = e; });
                          return;
                        }
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
            ],
          ),
        ),
      ),
    );
    // The sheet's route lets go of the field a beat after popping; disposing
    // under it red-screens ('_dependents.isEmpty').
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (Auth.signedIn && mounted) await _signedIn(null);
  }

  /// Recent screenshots need the photo library, and only the app can ask for
  /// it, so the ask belongs to this switch — never to moving on.
  Future<void> _wantScreenshots(bool on) async {
    if (!on) {
      setState(() {
        _screenshots = false;
        _photosNote = null;
      });
      return;
    }
    final granted = await GlyfBridge.screenshotAccess();
    if (!mounted) return;
    setState(() {
      _screenshots = granted;
      // Asked before and said no: iOS won't ask again, so say where it is
      // rather than let the switch flick back for no reason.
      _photosNote = granted ? null : 'Photos are off for Glyf. Allow them in Settings.';
    });
  }

  /// Onboarding is done once the tour is offered: settings saved, state
  /// written, so a phone closed on the offer opens to home next time.
  Future<void> _complete() async {
    await _saveFeel();
    await GlyfBridge.saveOnboardingState({
      'done': true,
      'persona': _persona,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
    Telemetry.log('onboarding_complete', {'persona': _persona ?? 'none'});
    unawaited(Auth.syncPrefs());
  }

  /// The website's chats on the real keyboard, from the one picked (or the
  /// first); home when it closes.
  Future<void> _startTour(int index) async {
    if (_leaving) return;
    _leaving = true;
    await _completing;
    if (!mounted) return;
    Telemetry.log('tour_start', {'from': tourScenarios[index].id});
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => DemoChat(startAt: index, onDone: () => Navigator.of(ctx).pop()),
    ));
    widget.onDone();
  }

  Future<void> _skipTour() async {
    if (_leaving) return;
    _leaving = true;
    await _completing;
    Telemetry.log('tour_skipped', {});
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    // Android's back gesture walks the steps too.
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: GlyfBackground(
          child: SafeArea(
            child: Column(children: [
              if (_steps[_step] != 'signin') _topBar(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 340),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                              begin: Offset(_forward ? 0.06 : -0.06, 0),
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
      ),
    );
  }

  /// Back on the left, the progress bar centred between two equal slots.
  Widget _topBar() {
    return SizedBox(
      height: 44,
      child: Row(children: [
        SizedBox(
          width: 52,
          child: AnimatedOpacity(
            opacity: _canGoBack ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_canGoBack,
              child: Semantics(
                identifier: 'onb:back',
                button: true,
                label: 'Back',
                child: IconButton(
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Glass.ink),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: _progress()),
        const SizedBox(width: 52),
      ]),
    );
  }

  Widget _progress() {
    return Padding(
      padding: EdgeInsets.zero,
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
          Center(
            // Three quick taps here open App Review's sign-in.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _reviewTap,
              child: TalkingOrb(
                size: 170,
                titleSize: 34,
                lines: const ['Hi, I’m {glyf}', 'Sign in to set up your AI keyboard.'],
                launchTarget: _launchStep == _step,
              ),
            ),
          ),
          const Spacer(flex: 3),
          // Apple and Google are the whole list: every Android phone has a
          // Google account, and an iPhone offering Google offers Apple too.
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
          if (_signInError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_signInError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: Glass.danger)),
            ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              key: const Key('onb:privacy'),
              onPressed: () => GlyfBridge.openURL(privacyPolicyURL),
              child: const Text('Privacy policy',
                  style: TextStyle(fontSize: 13, color: Glass.inkSoft, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 4),
        ]);

      case 'meet':
        return _frame(children: [
          const SizedBox(height: 18),
          Center(
            child: TalkingOrb(
              size: 116,
              titleSize: 28,
              launchTarget: _launchStep == _step,
              instant: _heard.contains('meet'),
              lines: const [
                'Let me remember you.',
                'When someone asks for your address or wallet, it’s one tap.',
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
        // While typing, nothing to tap by mistake sits over the keyboard: the
        // keyboard's Next walks the boxes, and the buttons come back after.
        final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
        final filled = _filledDetails;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: _frame(children: [
            const SizedBox(height: 10),
            Center(
              child: TalkingOrb(
                size: 76,
                titleSize: 26,
                lines: const ['What should I remember?'],
                instant: _heard.contains('details'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [
                for (final (i, (id, kind, label, hint)) in _detailFields.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      onTap: () => _detailFocus[id]!.requestFocus(),
                      child: Row(children: [
                        SizedBox(
                          width: 108,
                          child: Text(label,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          child: Semantics(
                            identifier: 'onb:detail:$id',
                            child: TextField(
                              controller: _details[id],
                              focusNode: _detailFocus[id],
                              autocorrect: kind == 'name' || kind == 'address',
                              keyboardType: switch (kind) {
                                'email' => TextInputType.emailAddress,
                                'phone' => TextInputType.phone,
                                'address' => TextInputType.streetAddress,
                                'social' => TextInputType.url,
                                _ => TextInputType.text,
                              },
                              textInputAction: i < _detailFields.length - 1
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              onSubmitted: (_) => i < _detailFields.length - 1
                                  ? _detailFocus[_detailFields[i + 1].$1]!.requestFocus()
                                  : FocusManager.instance.primaryFocus?.unfocus(),
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
            if (typing)
              const SizedBox(height: 8)
            else if (filled == 0) ...[
              _pill('Skip for now', onTap: _advance),
              const SizedBox(height: 20),
            ] else ...[
              _pill(filled == 1 ? 'Save 1 detail' : 'Save $filled details', onTap: _saveDetails),
              _skip(),
            ],
          ]),
        );

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
          _toggleCard('🖼️', 'Recent screenshots', _screenshots, _wantScreenshots),
          if (_photosNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Row(children: [
                Expanded(
                  child: Text(_photosNote!,
                      style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
                ),
                GestureDetector(
                  onTap: () => GlyfBridge.openSettings(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('Open',
                        style: TextStyle(
                            color: Glass.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          const Spacer(),
          _pill('Continue', onTap: _advance),
          const SizedBox(height: 20),
        ]);

      // Both things Glyf needs from the phone on one screen: each row opens
      // the place that turns it on.
      case 'setup':
        final android = Platform.isAndroid;
        final inUse = android ? _keyboardSelected : _fullAccess;
        // Android can see both from here. Full Access is a fact only the
        // keyboard itself can report — it lands the moment the keyboard next
        // runs — so on iPhone it is never what stands in the way; the
        // keyboard says so itself where it matters (the bar, search, paste).
        final done = android ? (_keyboardEnabled && inUse) : _keyboardEnabled;
        // While the keyboard is up the picture of a keyboard is the first
        // thing that can go.
        final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
        return _frame(children: [
          const Spacer(flex: 2),
          // Hidden, not removed: taking it out of the list would shuffle the
          // box below it and cost it the keyboard it just called up.
          Offstage(
            offstage: typing,
            child: const Column(children: [AiKeyboard(), SizedBox(height: 32)]),
          ),
          const GlyfText('Turn on {glyf}',
              style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w700, color: Glass.ink, letterSpacing: -0.9)),
          const SizedBox(height: 24),
          SetupChecklist(
            android: android,
            keyboardOn: _keyboardEnabled,
            inUseOn: inUse,
            onKeyboard: () => _openSetup('keyboard'),
            onInUse: () => _openSetup(android ? 'picker' : 'access'),
          ),
          // Full Access is real only when the keyboard itself says so, and it
          // says so by turning up: so once the keyboard is added, this is
          // where it gets its first word in.
          if (!android && _keyboardEnabled && !_fullAccess) ...[
            const SizedBox(height: 16),
            _tryHere(),
          ],
          const Spacer(flex: 3),
          Offstage(
            offstage: typing,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _pill('Continue', onTap: done ? _advance : null),
              if (!done) _skip() else const SizedBox(height: 20),
            ]),
          ),
        ]);

      // "Coffee near me" is only a real answer if the keyboard knows roughly
      // where you are. The APP asks — a keyboard extension cannot — and caches
      // a coarse fix for the search suite to send.
      case 'nearby':
        return _frame(children: [
          const Spacer(flex: 2),
          const Text('Search what\u2019s near you',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 30, height: 1.15, fontWeight: FontWeight.w700, color: Glass.ink, letterSpacing: -0.9)),
          const SizedBox(height: 22),
          NearbyDemo(settled: _locationOn),
          if (_locationOn)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_rounded, size: 17, color: Glass.success),
                SizedBox(width: 7),
                Text('Nearby search is on',
                    style: TextStyle(color: Glass.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ]),
            ),

          if (_locationNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_locationNote!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
            ),
          const Spacer(flex: 3),
          if (_locationOn)
            _pill('Continue', onTap: _advance)
          else
            _pill('Turn on nearby search', onTap: _enableLocation),
          if (!_locationOn) _skip(label: 'Not now'),
          if (_locationOn) const SizedBox(height: 20),
        ]);

      case 'calendar':
        final calendarDone = _calendarOn || _calendarAsked;
        return _frame(children: [
          const Spacer(flex: 2),
          const Text('Plan it where you chat',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 30, height: 1.15, fontWeight: FontWeight.w700, color: Glass.ink, letterSpacing: -0.9)),
          const SizedBox(height: 22),
          _statusRow(const Text('📅', style: TextStyle(fontSize: 20)), 'Calendar', _calendarOn,
              'onb:calendar:phone'),
          const SizedBox(height: 10),
          _statusRow(const GoogleMeetMark(size: 24), 'Google Meet', _meetOn, 'onb:calendar:google'),
          if (_calendarNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_calendarNote!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
            ),
          const Spacer(flex: 3),
          if (!calendarDone)
            _pill('Turn on calendar', onTap: _enableCalendar)
          else if (!_meetOn)
            _pill('Connect Google Meet', onTap: _busy ? null : _connectMeet)
          else
            _pill('Continue', onTap: _advance),
          if (!(calendarDone && _meetOn)) _skip(label: 'Not now'),
          if (calendarDone && _meetOn) const SizedBox(height: 20),
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
          _pill('Connect Google', onTap: _connectGoogle),
          _skip(label: 'Not now'),
        ]);

      case 'tour':
        // The cards run edge to edge so the next one peeks in; the rest
        // keeps the usual margins.
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 6),
          const Center(
            child: TalkingOrb(
              size: 84,
              titleSize: 30,
              lines: ['You’re all set', 'Try Glyf in a few real chats.'],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: TourPreview(onOpen: _startTour)),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _pill('See the tour', onTap: () => _startTour(0)),
              _skip(label: 'Skip tour', onTap: _skipTour, id: 'onb:skip-tour'),
            ]),
          ),
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
      setState(() => _connectNote = 'Engine offline. Connect later from Profile.');
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

  Widget _skip({String label = 'Skip', VoidCallback? onTap, String id = 'onb:skip'}) => Semantics(
        identifier: id,
        button: true,
        child: TextButton(
          onPressed: onTap ?? _advance,
          child: Text(label,
              style: const TextStyle(color: Glass.inkSoft, fontSize: 14)),
        ),
      );

  /// One thing the step turns on, and whether it is on.
  Widget _statusRow(Widget lead, String label, bool on, String id) => Semantics(
        identifier: id,
        label: '$label, ${on ? 'on' : 'off'}',
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            SizedBox(width: 26, child: Center(child: lead)),
            const SizedBox(width: 13),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Glass.ink, fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
            Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 22, color: on ? Glass.success : const Color(0xFFD3D6DD)),
          ]),
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
