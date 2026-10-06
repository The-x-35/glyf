import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../core/ai_consent.dart';
import '../core/auth.dart';
import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../profile/brand_marks.dart';
import 'setup_guide.dart';
import 'setup_hero.dart';
import 'talking_orb.dart';

/// Onboarding: sign in with Apple or Google, meet the orb, tell it what to
/// remember, make the keyboard yours, turn it on (with "What Glyf sends" as
/// a sheet on the first Open), then Maps, Calendar and Google Meet on one
/// screen, and home, where a floating button offers the tour. One screen,
/// steps slide through an AnimatedSwitcher (no PageView, so both humans and
/// UI tests can address everything directly).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone, this.resume = const {}, this.replay = false});

  /// What a previous run had saved when the app ended (its step and the
  /// persona picked): iOS kills the app the moment Full Access is granted
  /// in Settings, so coming back must land there, not on the hello.
  final Map<String, dynamic> resume;
  final VoidCallback onDone;

  /// Replayed from Profile by someone already set up: it starts at the top
  /// with their own settings, keeps `done` and the name, and closes at any
  /// step.
  final bool replay;

  /// This launch is someone coming back from Settings in the middle of
  /// setup: iOS ends the app the moment Full Access is allowed, so the next
  /// launch is them returning (welcome back, no launch film), not a fresh
  /// open. The trip is noted when Open is tapped.
  static bool backFromSettings(Map<String, dynamic> state) {
    if (state['step'] != 'setup') return false;
    final at = DateTime.tryParse('${state['settingsTripAt'] ?? ''}');
    return at != null && DateTime.now().toUtc().difference(at) < const Duration(minutes: 20);
  }

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  /// Arpit's order (2026-10-06). "What Glyf sends" is no screen of its own:
  /// it asks as a sheet the first time Turn on Glyf opens Settings or the
  /// picker, still before anything can be sent. Maps, Calendar and Meet share
  /// one screen ('tools'), and there is no tour offer at the end: Home has a
  /// floating "Take a tour" button (the app, then the chats) instead.
  static const _steps = <String>['signin', 'meet', 'details', 'feel', 'setup', 'tools'];
  int _step = 0;

  /// Which way the last step change went, for the slide.
  bool _forward = true;

  /// Steps already seen: coming back to one, its orb doesn't talk again.
  final Set<String> _heard = {};

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
  static const _detailLabelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);

  /// The label column fits the longest label ("Wallet address") and a gap,
  /// measured in the labels' own type at the phone's text size: a fixed
  /// 108 let it run into its placeholder on both phones.
  double _detailLabelWidth(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(_detailLabelStyle);
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final f in _detailFields) {
      final p = TextPainter(
        text: TextSpan(text: f.$3, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, p.width);
      p.dispose();
    }
    return widest.ceilToDouble() + 14;
  }
  String? _detailsError;
  /// Why the screenshots switch wouldn't stay on, when it wouldn't.
  String? _photosNote;
  /// When this run of the setup step began: only what the keyboard says
  /// after this counts as proof of Full Access.
  DateTime? _setupSince;
  /// Relaunched by coming back from Settings (iOS ended the app when Full
  /// Access was allowed): the setup step says why, rather than starting cold.
  bool _welcomeBack = false;
  /// Setup went from not done to done while on screen: the moment is said.
  bool _celebrate = false;
  /// Android: Glyf was picked from the box, so the box stays to try it in.
  bool _glyfInBox = false;
  /// The box the keyboard is asked to turn up in.
  final _try = TextEditingController();
  final _tryFocus = FocusNode();
  /// The saved switches being read: saving waits for it, so the defaults
  /// below never go over someone's own settings.
  Future<void>? _feelLoad;
  bool _keySounds = true;
  bool _haptics = true;
  /// On by default, like Gboard: what you copy is there to paste later.
  bool _clipboard = true;
  /// Off until asked for: turning it on is what asks for the photo library.
  bool _screenshots = true;
  bool _keyboardEnabled = false;
  bool _fullAccess = false;
  bool _keyboardSelected = false;
  bool _locationOn = false;
  String? _locationNote;
  /// The calendar step: the phone's calendar for the keyboard, and Google
  /// Meet (Google Calendar and Meet) when sign-in didn't bring it.
  bool _calendarOn = false;
  bool _meetOn = false;
  String? _calendarNote;
  String? _meetNote;
  /// Wallet address, X and Telegram wait under More (Arpit, 2026-10-06).
  bool _moreDetails = false;
  static const _mainDetails = 4;
  Timer? _poll;

  // Sign-in
  bool _busy = false;
  String? _signInError;
  bool _meetDone = false;

  /// The step on screen when the app opened: the launch bubble lands on its orb.
  late final int _launchStep;

  @override
  void initState() {
    Auth.reviewSignInAvailable().then((on) {
      if (mounted && on) setState(() => _reviewDoor = true);
    });
    super.initState();
    // Already signed in (onboarding was left half way): start after sign-in.
    if (Auth.signedIn) _step = 1;
    // A replay starts at the top, with the switches as they are now.
    if (widget.replay) {
      _feelLoad = _loadFeel();
      unawaited(_loadLocation());
    }
    // …and where it was left, when that is known: granting Full Access ends
    // the app (tccd: "access to kTCCServiceKeyboardNetwork changed"), so
    // the setup step in particular must survive a relaunch.
    // Steps that have gone since (a state saved by an older build) reopen
    // where their questions went.
    final resume = switch (widget.replay ? null : widget.resume['step'] as String?) {
      'ai' => 'setup',
      'nearby' || 'calendar' => 'tools',
      final step => step,
    };
    final at = resume == null ? -1 : _steps.indexOf(resume);
    if (Auth.signedIn && at > 1) {
      _step = at;
      _heard.addAll(_steps.take(at));
      _persona ??= widget.resume['persona'] as String?;
      // Choices made on the way here were saved as they were made.
      if (at > _steps.indexOf('feel')) _feelLoad = _loadFeel();
      if (resume == 'tools') {
        unawaited(_loadLocation());
        unawaited(_loadCalendarStep());
      }
      if (resume == 'details') _prefillFromAccount();
      if (resume == 'setup') {
        _setupSince = DateTime.now().toUtc();
        _welcomeBack = OnboardingFlow.backFromSettings(widget.resume);
        // Ask the keyboard to turn up and say whether it has Full Access
        // now, instead of leaving the person to find the box. (Android has
        // no such question; its guide stays in view instead.)
        if (!Platform.isAndroid) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_fullAccess) _tryFocus.requestFocus();
          });
        }
      }
    }
    _launchStep = _step;
    for (final c in _details.values) {
      c.addListener(_detailsChanged);
    }
    _tryFocus.addListener(_tryFocusChanged);
    Telemetry.log('onboarding_step_view', {'step': _steps[_step]});
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _checkStatus());
    // At once too: a relaunch on the setup step shouldn't show a second of
    // unticked rows (and the wrong guide) before the first tick.
    unawaited(_checkStatus());
  }

  /// Where we are, for a relaunch. Sign-in has nothing to come back to.
  void _remember() {
    final name = _steps[_step];
    if (name == 'signin') return;
    unawaited(_saveState({
      'step': name,
      if (_persona != null) 'persona': _persona,
      // A Settings trip only explains a relaunch on the setup step.
      if (name != 'setup') 'settingsTripAt': null,
    }));
  }

  /// Onboarding's own keys written over what onboarding.json holds, never
  /// in place of it: `done` and the name set in Profile stay.
  Future<void> _saveState(Map<String, dynamic> changes) async {
    final state = await GlyfBridge.onboardingState();
    await GlyfBridge.saveOnboardingState({...state, ...changes});
  }

  /// The "Make it yours" switches, kept in shared settings the moment that
  /// step is left — so a relaunch keeps them, and the keyboard sees them.
  Future<void> _saveFeel() async {
    await _feelLoad;
    await GlyfBridge.updateSharedSettings((s) {
      s['keyClicks'] = _keySounds;
      s['haptics'] = _haptics;
      s['clipboardHistory'] = _clipboard;
      s['clipboardScreenshots'] = _screenshots;
      return s;
    });
  }

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

  /// The practice box stays while it has the cursor (Glyf may be up in it).
  void _tryFocusChanged() {
    if (mounted && _steps[_step] == 'setup') setState(() {});
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
      _meetNote = error;
    });
    Telemetry.log('onboarding_google_meet', {'granted': _meetOn});
  }

  /// Where the keyboard gets to speak for itself: on iPhone, type one letter
  /// with Glyf and it reports Full Access, which nothing else on the phone
  /// can tell us; on Android the picker opens over it and Glyf appears in it.
  Widget _tryHere() => Column(
      key: const ValueKey('onb:setup:try-box'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text(
              !Platform.isAndroid
                  ? 'Tap 🌐 on the keyboard and pick Glyf'
                  : !_keyboardSelected
                      ? 'Pick Glyf Keyboard in the list'
                      : _tryFocus.hasFocus
                          ? 'This is Glyf. Type a few words.'
                          : 'Tap the box to try Glyf',
              style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
        ),
      ]);

  /// Takes them where the thing they tapped is turned on.
  Future<void> _openSetup(String what) async {
    Telemetry.log('onboarding_setup_open', {'what': what});
    // "What Glyf sends" is asked here, once, before the keyboard can be
    // turned on (Google Play and Apple want a yes before anything is sent),
    // as a sheet rather than a screen of its own (Arpit, 2026-10-06: "can
    // we remove what glyf sends screen that doesnt look good").
    if (await AiConsent.needed()) {
      if (!mounted) return;
      await showAiConsentSheet(context);
      if (!mounted) return;
    }
    if (what == 'picker') {
      unawaited(_choosePicker());
      return;
    }
    // iOS shows "Paste from Other Apps" only for an app that has asked to
    // paste: Glyf asks once before Settings opens.
    if (what == 'paste' && !await GlyfBridge.askPasteOnce()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Copy anything first, then tap Open')));
      }
      return;
    }
    // iOS may end the app while they're in Settings (allowing Full Access
    // does), so the trip is noted: the next launch is a welcome back.
    if (!Platform.isAndroid) {
      unawaited(_saveState({'step': 'setup', 'settingsTripAt': DateTime.now().toUtc().toIso8601String()}));
    }
    GlyfBridge.openSettings();
  }

  /// Android shows its keyboard picker only to an app with a box being typed
  /// in (Android 16 drops the request otherwise, which left "Choose" doing
  /// nothing): the practice box takes the cursor first, and the picker opens
  /// over the keyboard it brings up, where Glyf appears once it's picked.
  Future<void> _choosePicker() async {
    if (!_tryFocus.hasFocus) {
      _tryFocus.requestFocus();
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
    if (mounted) await GlyfBridge.showImePicker();
  }

  /// iPhone: Glyf turned up with Full Access. Android: Glyf is picked.
  bool get _setupDone => Platform.isAndroid
      ? _keyboardEnabled && _keyboardSelected
      : _keyboardEnabled && _fullAccess;

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
    final hadPicked = _keyboardSelected;
    final wasDone = _setupDone;
    setState(() {
      _keyboardEnabled = enabled;
      _keyboardSelected = selected;
      _fullAccess = enabled && fresh && ping?['hasFullAccess'] == true;
      if (!wasDone && _setupDone && _steps[_step] == 'setup') _celebrate = true;
    });
    // The keyboard came up to say so. Now that it has, it can go, and the
    // Continue it was covering comes back.
    if (!hadAccess && _fullAccess && _tryFocus.hasFocus) _tryFocus.unfocus();
    // Android: Glyf was just picked. Picking a keyboard doesn't raise it, and
    // Android won't raise it for the app either (only for a tap), so the box
    // lets go and stays, asking for that tap: Glyf comes up in it, with
    // Continue over it.
    if (Platform.isAndroid && !hadPicked && selected && _tryFocus.hasFocus) {
      setState(() => _glyfInBox = true);
      _tryFocus.unfocus();
    }
  }

  void _advance() {
    Telemetry.log('onboarding_step_complete', {'step': _steps[_step]});
    // The last step finishes onboarding: home, where the tour waits.
    if (_step >= _steps.length - 1) {
      unawaited(_finish());
      return;
    }
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
    if (_steps[_step] == 'tools') {
      unawaited(_loadLocation());
      unawaited(_loadCalendarStep());
    }
    Telemetry.log('onboarding_step_view', {'step': _steps[_step]});
  }

  /// Back is there once signed in and past the orb's hello.
  bool get _canGoBack => _step > _steps.indexOf('meet') && !_busy;

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
  /// The server says while a submission is in review (REVIEW_PASSWORD set);
  /// otherwise the link and the taps do nothing at all.
  bool _reviewDoor = false;

  void _reviewTap() {
    if (!_reviewDoor) return;
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
              const Text('The sign-in information from App Store Connect.',
                  style: TextStyle(fontSize: 13.5, color: Glass.inkSoft)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Glass.hairline),
                ),
                child: const Row(
                  children: [
                    Text('User name', style: TextStyle(fontSize: 13.5, color: Glass.inkSoft)),
                    Spacer(),
                    Text('review@tryglyf.com',
                        style: TextStyle(fontSize: 14, color: Glass.ink, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
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

  /// Onboarding is done: settings saved and state written.
  Future<void> _complete() async {
    await _saveFeel();
    await _saveState({
      'done': true,
      if (_persona != null) 'persona': _persona,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
    // A replay from Profile is no second sign-up.
    if (!widget.replay) Telemetry.log('onboarding_complete', {'persona': _persona ?? 'none'});
    unawaited(Auth.syncPrefs());
  }

  /// The last step's Continue: saved as done, then home, where a floating
  /// "Take a tour" button offers the app and then the chats.
  Future<void> _finish() async {
    if (_leaving) return;
    _leaving = true;
    await _complete();
    if (mounted) widget.onDone();
  }

  /// A replay's Close: out at once, from any step.
  void _close() {
    if (_leaving) return;
    _leaving = true;
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
              if (_steps[_step] != 'signin' || widget.replay) _topBar(),
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
        SizedBox(
          width: 52,
          child: widget.replay
              ? Semantics(
                  identifier: 'onb:close',
                  button: true,
                  label: 'Close',
                  child: IconButton(
                    onPressed: _close,
                    icon: const Icon(Icons.close_rounded, size: 22, color: Glass.ink),
                  ),
                )
              : null,
        ),
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
          // Plainly there for Apple's reviewer while a submission is in
          // review (the server's REVIEW_PASSWORD switches it); gone the rest
          // of the time. The ASC notes point at it.
          if (_reviewDoor) ...[
            const SizedBox(height: 2),
            Center(
              child: TextButton(
                key: const Key('onb:review'),
                onPressed: _busy ? null : _showReviewSignIn,
                child: const Text('App Review sign-in',
                    style: TextStyle(fontSize: 12.5, color: Glass.inkSoft, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
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
        final labelWidth = _detailLabelWidth(context);
        // Name, Email, Phone and Home; the rest under More, unless one of
        // them already holds something.
        final more = _moreDetails ||
            _detailFields.skip(_mainDetails).any((f) => _details[f.$1]!.text.trim().isNotEmpty);
        final shown = more ? _detailFields : _detailFields.take(_mainDetails).toList();
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
                for (final (i, (id, kind, label, hint)) in shown.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      onTap: () => _detailFocus[id]!.requestFocus(),
                      child: Row(children: [
                        SizedBox(
                          width: labelWidth,
                          child: Text(label, maxLines: 1, softWrap: false, style: _detailLabelStyle),
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
                              textInputAction: i < shown.length - 1
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              onSubmitted: (_) => i < shown.length - 1
                                  ? _detailFocus[shown[i + 1].$1]!.requestFocus()
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
                if (!more)
                  Semantics(
                    identifier: 'onb:details:more',
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _moreDetails = true),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                        child: Row(children: [
                          const Icon(Icons.add_circle_outline_rounded, size: 20, color: Glass.accent),
                          const SizedBox(width: 8),
                          const Text('More',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Glass.accent)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _detailFields.skip(_mainDetails).map((f) => f.$3).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, color: Glass.inkSoft),
                            ),
                          ),
                        ]),
                      ),
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
        // While the keyboard is up the pictures are the first thing to go.
        final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
        // The phone's own screens, for whatever is left to do; once it's all
        // done, iPhone shows how to switch to Glyf and keep it first.
        final guide = android
            ? (!_keyboardEnabled ? androidTurnOn : !inUse ? androidPick : const <GuideStep>[])
            : (!_keyboardEnabled ? iosTurnOn : !_fullAccess ? iosAccess : iosUse);
        return _frame(children: [
          _setupBanner(),
          // Hidden, not removed: taking it out of the list would shuffle the
          // box below it and cost it the keyboard it just called up.
          Expanded(
            child: Offstage(
              offstage: typing,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: guide.isEmpty ? const Center(child: AiKeyboard()) : SetupGuide(steps: guide),
              ),
            ),
          ),
          const GlyfText('Turn on {glyf}',
              style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w700, color: Glass.ink, letterSpacing: -0.9)),
          const SizedBox(height: 20),
          SetupChecklist(
            android: android,
            keyboardOn: _keyboardEnabled,
            inUseOn: inUse,
            onKeyboard: () => _openSetup('keyboard'),
            onInUse: () => _openSetup(android ? 'picker' : 'access'),
            // Android never asks to paste; the iPhone does until this is Allow.
            onPaste: android ? null : () => _openSetup('paste'),
          ),
          // The practice box. iPhone: Full Access is real only when the
          // keyboard itself says so, by turning up here. Android: the picker
          // needs a box being typed in, and Glyf shows up in it. It stays
          // while it has the cursor, so Glyf isn't snatched away mid-look.
          if (_keyboardEnabled && (!inUse || _tryFocus.hasFocus || _glyfInBox)) ...[
            const SizedBox(height: 16),
            _tryHere(),
          ],
          const SizedBox(height: 18),
          // Nothing to tap by mistake over the keyboard, until it's all done:
          // then Continue sits over Glyf, free to be tried first.
          Offstage(
            offstage: typing && !_setupDone,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _pill('Continue', onTap: done ? _advance : null),
              if (!done) _skip() else const SizedBox(height: 20),
            ]),
          ),
        ]);

      // Maps, Calendar and Meet on one screen (Arpit, 2026-10-06: "i think we
      // can combine maps, calendar and meet thing in one screen"). Each row
      // asks for its own permission when tapped; Continue works whenever.
      // Location: "coffee near me" is only a real answer if the keyboard knows
      // roughly where you are, and the APP has to ask (a keyboard cannot).
      case 'tools':
        return _frame(children: [
          const Spacer(flex: 2),
          const Text('Connect your tools',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 30, height: 1.15, fontWeight: FontWeight.w700, color: Glass.ink, letterSpacing: -0.9)),
          const SizedBox(height: 8),
          const Text('Places near you, your day and Meet links, right where you type.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: Glass.inkSoft)),
          const SizedBox(height: 26),
          _toolRow(
            id: 'onb:tools:maps',
            lead: const Text('📍', style: TextStyle(fontSize: 21)),
            title: 'Maps',
            detail: 'Find places near you, like coffee near me',
            on: _locationOn,
            action: 'Turn on',
            onTap: _enableLocation,
            note: _locationNote,
          ),
          const SizedBox(height: 10),
          _toolRow(
            id: 'onb:tools:calendar',
            lead: const Text('📅', style: TextStyle(fontSize: 21)),
            title: 'Calendar',
            detail: 'See your day and add plans from a chat',
            on: _calendarOn,
            action: 'Turn on',
            onTap: _enableCalendar,
            note: _calendarNote,
          ),
          const SizedBox(height: 10),
          _toolRow(
            id: 'onb:tools:meet',
            lead: const GoogleMeetMark(size: 24),
            title: 'Google Meet',
            detail: 'Make Meet links for your plans',
            on: _meetOn,
            action: 'Connect',
            onTap: _busy ? null : _connectMeet,
            note: _meetNote,
          ),
          const Spacer(flex: 3),
          _pill('Continue', onTap: _advance),
          const SizedBox(height: 20),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── pieces ──────────────────────────────────────────────────────────────

  /// Over the setup step: why the app just restarted (iOS ends it when Full
  /// Access is allowed), and the moment Glyf is on and working.
  Widget _setupBanner() {
    final android = Platform.isAndroid;
    final Widget banner;
    if (_celebrate || (_welcomeBack && _setupDone)) {
      banner = _note(
        key: const ValueKey('onb:setup:done'),
        icon: Icons.check_circle_rounded,
        color: Glass.success,
        title: android ? 'Glyf is your keyboard' : 'Glyf is on',
        body: android ? 'It’s on and in use. You’re ready to type.' : 'Full Access is on too. You’re ready to type.',
      );
    } else if (_welcomeBack) {
      banner = _note(
        key: const ValueKey('onb:setup:welcome-back'),
        icon: Icons.waving_hand_rounded,
        color: Glass.accent,
        title: 'Welcome back',
        body: 'Your iPhone restarts Glyf when you allow Full Access. You’re right where you left off.',
      );
    } else {
      banner = const SizedBox(key: ValueKey('onb:setup:none'), width: double.infinity);
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: banner),
    );
  }

  Widget _note({
    required Key key,
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) =>
      Semantics(
        key: key,
        identifier: key is ValueKey<String> ? key.value : null,
        liveRegion: true,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Glass.ink)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 13, height: 1.35, color: Glass.inkSoft)),
              ]),
            ),
          ]),
        ),
      );

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

  /// One tool on the Connect your tools step: what it's for, and either its
  /// own Turn on (which asks the phone) or a tick once it's on. What went
  /// wrong, if anything, says so under the row.
  Widget _toolRow({
    required String id,
    required Widget lead,
    required String title,
    required String detail,
    required bool on,
    required String action,
    required VoidCallback? onTap,
    String? note,
  }) =>
      Semantics(
        identifier: id,
        label: '$title, ${on ? 'on' : 'off'}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
            onTap: on ? null : onTap,
            child: Row(children: [
              SizedBox(width: 28, child: Center(child: lead)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(color: Glass.ink, fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(detail, style: const TextStyle(color: Glass.inkSoft, fontSize: 13, height: 1.3)),
                ]),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: on
                    ? const Padding(
                        key: ValueKey('on'),
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.check_circle_rounded, size: 24, color: Glass.success),
                      )
                    : Container(
                        key: const ValueKey('off'),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: Glass.accent.withValues(alpha: onTap == null ? 0.05 : 0.11),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(action,
                            style: TextStyle(
                                color: onTap == null ? Glass.inkSoft : Glass.accent,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700)),
                      ),
              ),
            ]),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Text(note, style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
            ),
        ]),
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
