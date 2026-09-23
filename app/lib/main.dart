import 'package:flutter/material.dart';

import 'core/auth.dart';
import 'core/bridge.dart';
import 'core/catalog.dart';
import 'core/telemetry.dart';
import 'core/theme.dart';
import 'dictation/recording_sheet.dart';
import 'launch/launch_overlay.dart';
import 'onboarding/demo_chat.dart';
import 'wallet/wallet_screen.dart';
import 'onboarding/onboarding_flow.dart';
import 'profile/connected_tools_screen.dart';
import 'profile/keyboard_screen.dart';
import 'shell/app_shell.dart';
import 'vault/vault_screen.dart';

void main() => runApp(const GlyfApp());

final navigatorKey = GlobalKey<NavigatorState>();

class GlyfApp extends StatefulWidget {
  const GlyfApp({super.key});

  @override
  State<GlyfApp> createState() => _GlyfAppState();
}

class _GlyfAppState extends State<GlyfApp> with WidgetsBindingObserver {
  // Default to the funnel; flip to home once saved state proves completion.
  bool _onboarded = false;
  /// What onboarding had saved when the last run was cut short: the step
  /// to reopen on and the persona picked.
  Map<String, dynamic> _resume = const {};
  /// Until the saved session has been read, nothing is shown.
  bool _ready = false;

  /// The launch animation plays over the app until it has handed off.
  bool _launching = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GlyfBridge.onDeepLink(_handleLink);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final state = await GlyfBridge.onboardingState();
    // Nobody uses Glyf signed out: without a session, onboarding runs again.
    final signedIn = await Auth.restore();
    if (!mounted) return;
    setState(() {
      _onboarded = state['done'] == true && signedIn;
      // A run that was cut short (iOS ends the app when Full Access is
      // granted) picks up at the step it was on.
      _resume = _onboarded ? const {} : state;
      _ready = true;
    });
    if (signedIn) {
      Auth.syncProfile();
      Auth.syncPrefs();
    }
    // Custom glyf names live in shared settings — warm the sync cache.
    final settings = await GlyfBridge.sharedSettings();
    Catalog.rememberCustomTitles(
        settings['customTitles'] as Map<String, dynamic>?);
    Telemetry.log('app_open');
    // A tour that ended with the app killed never cleared its hint.
    GlyfBridge.updateSharedSettings((s) {
      s.remove('tourHint');
      s.remove('tourHintAt');
      s.remove('tourStep');
      return s;
    });
    // The keyboard may have parked an intent before we ever launched
    // (Spike A fallback path) — pick it up.
    _checkPendingDictation();
    // A glyf:// link that started the app arrived before anything here was
    // listening; the platform kept it for us.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final link = await GlyfBridge.lastDeepLink();
      if (link != null && mounted) _handleLink(link);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPendingDictation();
  }

  void _handleLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (uri.host == 'intent') {
      final id = uri.queryParameters['id'];
      if (id != null) _openDictation(id);
    }
    if (uri.host == 'open' && uri.queryParameters['path']?.startsWith('wallet') == true) {
      // The keyboard saw an address and an amount; the wallet takes it from
      // here, because signing belongs in the app.
      final path = Uri.parse(uri.queryParameters['path']!);
      // Inside the tour, Semi's payment is practised, never sent.
      final practice = DemoChat.onPracticePay;
      if (practice != null) {
        practice(path.queryParameters['to'], path.queryParameters['amount']);
        return;
      }
      _openWallet(path.queryParameters['to'], path.queryParameters['amount']);
      return;
    }
    if (uri.host == 'open') {
      // The keyboard's "Open in Glyf app" footers and its Connect button
      // name the screen they came from; each lands on its counterpart here.
      switch (uri.queryParameters['path'] ?? '') {
        case 'build': // "Build your own" from the keyboard's My glyfs list.
          AppShell.requestedTab.value = 1;
          return;
        case 'keys':
          AppShell.requestedTab.value = 0;
          return;
        case 'vault':
          _push((_) => const VaultScreen());
          return;
        case 'connectors':
        case 'connected':
          _push((_) => const ConnectedToolsScreen());
          return;
        case 'settings':
          _push((_) => const KeyboardScreen());
          return;
      }
    }
    if (uri.host == 'demo') {
      _openDemo();
      return;
    }
    if (uri.host == 'connected') {
      // OAuth consent round-trip landed (§6.11).
      final ok = uri.queryParameters['ok'] == 'true';
      Telemetry.log('connector_connected', {
        'provider': uri.queryParameters['provider'] ?? '?',
        'ok': ok,
      });
      final messenger = navigatorKey.currentContext == null
          ? null
          : ScaffoldMessenger.maybeOf(navigatorKey.currentContext!);
      messenger?.showSnackBar(SnackBar(
          content: Text(ok
              ? 'Google connected'
              : 'Google connection didn’t finish')));
    }
  }

  void _push(WidgetBuilder builder) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(MaterialPageRoute(builder: builder));
  }

  void _openWallet(String? to, String? amount) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (c) => WalletScreen(prefillTo: to, prefillAmount: amount),
    ));
  }

  /// glyf://demo — replay the guided tour any time, from Settings or a link.
  void _openDemo() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (c) => DemoChat(onDone: () => Navigator.of(c).pop()),
    ));
  }

  Future<void> _checkPendingDictation() async {
    final id = await GlyfBridge.dictationPendingIntent();
    if (id != null) _openDictation(id);
  }

  bool _sheetOpen = false;

  Future<void> _openDictation(String intentId) async {
    final nav = navigatorKey.currentState;
    if (nav == null || _sheetOpen) return;
    _sheetOpen = true;
    try {
      await RecordingSheet.open(nav, intentId);
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glyf',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: Glass.theme(),
      builder: (context, child) => Stack(children: [
        if (child != null) Positioned.fill(child: child),
        if (_launching)
          Positioned.fill(
            child: LaunchOverlay(
              ready: _ready,
              handToOrb: !_onboarded,
              onDone: () => setState(() => _launching = false),
            ),
          ),
      ]),
      home: !_ready
          ? const Scaffold(backgroundColor: Glass.bg)
          : _onboarded
              ? AppShell(onRerunOnboarding: () => setState(() => _onboarded = false))
              : OnboardingFlow(resume: _resume, onDone: () => setState(() => _onboarded = true)),
    );
  }
}
