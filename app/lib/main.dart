import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import 'core/auth.dart';
import 'core/billing.dart';
import 'core/bridge.dart';
import 'core/catalog.dart';
import 'core/funnel.dart';
import 'core/telemetry.dart';
import 'core/theme.dart';
import 'dictation/recording_sheet.dart';
import 'launch/launch_overlay.dart';
import 'onboarding/demo_chat.dart';
import 'wallet/buy_screen.dart';
import 'wallet/crypto_pay.dart';
import 'wallet/pay_launch_screen.dart';
import 'wallet/pay_status_screen.dart';
import 'evm/evm_wallet.dart';
import 'evm/evm_wallet_screen.dart';
import 'evm/trade_screen.dart';
import 'wallet/send_screen.dart';
import 'wallet/wallet_screen.dart';
import 'wallet/wallet_flow.dart';
import 'onboarding/onboarding_flow.dart';
import 'onboarding/tour_scenarios.dart';
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
    Auth.dropped.addListener(_signInAgain);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Auth.dropped.removeListener(_signInAgain);
    super.dispose();
  }

  /// The server turned the session away and Auth dropped it: back to
  /// sign-in, the way signing out goes, so nothing reads signed in.
  void _signInAgain() {
    if (mounted && _onboarded && !Auth.signedIn) setState(() => _onboarded = false);
  }

  Future<void> _load() async {
    final state = await GlyfBridge.onboardingState();
    // Back from Settings in the middle of setup (iOS ends the app when Full
    // Access is allowed): they're returning, so no launch film.
    if (OnboardingFlow.backFromSettings(state) && mounted) setState(() => _launching = false);
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
      Billing.sync();
      CryptoPay.resume();
    }
    Billing.listen();
    WalletFlow.load();
    WalletFlow.loadEnabled();
    _loadEvmWallet();
    // Custom glyf names live in shared settings — warm the sync cache.
    final settings = await GlyfBridge.sharedSettings();
    Catalog.rememberCustomTitles(
        settings['customTitles'] as Map<String, dynamic>?);
    Telemetry.log('app_open');
    Funnel.report();
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
    if (state == AppLifecycleState.resumed) {
      Funnel.report();
      _checkPendingDictation();
      if (_onboarded) {
        Billing.sync();
        CryptoPay.resume();
      }
    }
  }

  /// The Glyf wallet's address reaches the keyboard on every launch; UI
  /// tests make one with `--glyf-test-evm-wallet` (never in a release build).
  Future<void> _loadEvmWallet() async {
    if (!kReleaseMode && (await GlyfBridge.launchArgs()).contains('--glyf-test-evm-wallet')) {
      await EvmWallet.ensure();
      return;
    }
    await EvmWallet.load();
  }

  Future<void> _handleLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (uri.host == 'intent') {
      final id = uri.queryParameters['id'];
      if (id != null) _openDictation(id);
    }
    if (uri.host == 'phantom') {
      // Phantom's answer to Connect or to a payment: finished on its own
      // screen, which sends the signed payment on.
      _push('phantom', (_) => PayStatusScreen(reply: uri), link: link);
      return;
    }
    if (uri.host == 'open' && uri.queryParameters['path']?.startsWith('trade') == true) {
      // The keyboard read a trade and quoted it: the Glyf wallet signs it here.
      final q = Uri.parse(uri.queryParameters['path']!).queryParameters;
      _push('trade', (_) => TradeScreen(query: q), link: link);
      return;
    }
    if (uri.host == 'open' && uri.queryParameters['path'] == 'evm-wallet') {
      _push('evm-wallet', (_) => const EvmWalletScreen(), replace: false);
      return;
    }
    if (uri.host == 'open' && uri.queryParameters['path']?.startsWith('pay') == true) {
      // The keyboard's pay strip took the amount already: this is the flash
      // on the way into Phantom. Inside the tour it stays practice.
      final path = Uri.parse(uri.queryParameters['path']!);
      final q = path.queryParameters;
      final practice = DemoChat.onPracticePay;
      if (practice != null) {
        practice(q['to'], q['amount'] ?? q['usd']);
        return;
      }
      // With the wallet off, a pay link does nothing (2026-10-14).
      await WalletFlow.loadEnabled();
      if (!WalletFlow.enabled.value) return;
      _push('pay', (_) => PayLaunchScreen(query: q), link: link);
      return;
    }
    if (uri.host == 'open' && uri.queryParameters['path']?.startsWith('wallet') == true) {
      // The keyboard saw an address and an amount; the wallet takes it from
      // here, because signing belongs in Phantom, opened by the app.
      final path = Uri.parse(uri.queryParameters['path']!);
      final to = path.queryParameters['to'];
      // The strip's Pay tool, with nobody to pay yet: the wallet itself.
      await WalletFlow.loadEnabled();
      if (!WalletFlow.enabled.value) return;
      if (to == null) {
        _push('wallet', (_) => const WalletScreen(), replace: false);
        return;
      }
      // Inside the tour, Semi's payment is practised, never sent.
      final practice = DemoChat.onPracticePay;
      if (practice != null) {
        practice(to, path.queryParameters['amount']);
        return;
      }
      _push(
          'send',
          (_) => SendScreen(
                to: to,
                amount: path.queryParameters['amount'],
                token: path.queryParameters['token'],
              ),
          link: link);
      return;
    }
    if (uri.host == 'open' && uri.queryParameters['path']?.startsWith('buy') == true) {
      // A contract address or a ticker the keyboard saw: buy it here.
      final path = Uri.parse(uri.queryParameters['path']!);
      _push('buy', (_) => BuyScreen(query: path.queryParameters['mint'] ?? path.queryParameters['symbol']),
          link: link);
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
          _push('vault', (_) => const VaultScreen(), replace: false);
          return;
        case 'connectors':
        case 'connected':
          _push('connected', (_) => const ConnectedToolsScreen(), replace: false);
          return;
        case 'settings':
          _push('settings', (_) => const KeyboardScreen(), replace: false);
          return;
      }
    }
    if (uri.host == 'demo') {
      // glyf://demo?chat=investor opens that chat of the tour.
      final chat = uri.queryParameters['chat'];
      _openDemo(at: chat == null ? 0 : tourScenarios.indexWhere((s) => s.id == chat));
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

  /// Opens a deep link's screen. Every link used to push one more, so taps
  /// from the keyboard stacked copies: the same screen already on top stays
  /// (same link, or [replace] off) or is swapped for the new link's.
  void _push(String name, WidgetBuilder builder,
      {String? link, bool replace = true, bool fullscreenDialog = false}) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    Route<dynamic>? top;
    // Pops nothing: the first route asked is the top one.
    nav.popUntil((r) {
      top = r;
      return true;
    });
    final route = MaterialPageRoute<void>(
      builder: builder,
      fullscreenDialog: fullscreenDialog,
      settings: RouteSettings(name: name, arguments: link),
    );
    if (top?.settings.name != name) {
      nav.push(route);
    } else if (replace && top?.settings.arguments != link) {
      nav.pushReplacement(route);
    }
  }

  /// glyf://demo — replay the guided tour any time, from Settings or a link.
  void _openDemo({int at = 0}) => _push(
      'demo', (c) => DemoChat(startAt: at < 0 ? 0 : at, onDone: () => Navigator.of(c).pop()),
      replace: false, fullscreenDialog: true);

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
