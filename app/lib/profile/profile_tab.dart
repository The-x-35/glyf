import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoAlertDialog, CupertinoDialogAction, showCupertinoDialog;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/billing.dart';
import 'connected_tools_screen.dart';
import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/text_sheet.dart';
import '../core/theme.dart';
import '../shell/app_tour.dart';
import '../onboarding/onboarding_flow.dart';
import '../wallet/solana.dart' show Sol;
import '../wallet/wallet_flow.dart' show WalletFlow, WalletLink;
import '../wallet/wallet_screen.dart';
import '../vault/vault_screen.dart';
import '../vocab/vocabulary_screen.dart';
import 'brand_marks.dart' show GoogleG;
import 'code_screen.dart';
import 'keyboard_screen.dart';
import 'paywall_sheet.dart';
import 'search_sheet.dart';

/// Settings on one short page: the account card, a row per place, and the
/// account's own actions at the foot. It had grown a row per switch; now a
/// row that only holds a switch or two (Search) or a choice (Tour) opens a
/// sheet, and Tone profile lives with the words in Vocabulary.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.onRerunOnboarding, this.activeTab});
  final VoidCallback onRerunOnboarding;

  /// The shell's selected tab: the refresh rests while another one shows.
  final ValueListenable<int>? activeTab;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> with WidgetsBindingObserver {
  Map<String, dynamic> _settings = {};
  String _displayName = 'You';
  bool _serverUp = false;
  int? _remaining;
  /// The plan the server is enforcing, when it answered; the phone's own
  /// claim is only a fallback while offline.
  String? _serverPlan;
  int? _perDay;
  /// Private payments are always on; calendar and contacts when connected.
  int _connectedTools = 0;
  bool _contactsOn = false;
  bool _nearbyOn = false;
  /// The App Store has Plus and Max to sell (it answered with them).
  bool _onSale = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.activeTab?.addListener(_onTab);
    _refresh();
    _startPoll();
    Billing.products().then((found) {
      if (mounted) setState(() => _onSale = found.isNotEmpty);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.activeTab?.removeListener(_onTab);
    _poll?.cancel();
    super.dispose();
  }

  bool get _visible => (widget.activeTab?.value ?? 2) == 2;

  /// Local state is cheap to re-read; the two server calls in here are
  /// not, and every 5 s was 24 requests a minute from one idle screen. It
  /// rests while another tab shows or the app is away.
  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_visible) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_visible) _refresh();
      _startPoll();
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _onTab() {
    if (_visible) _refresh();
  }

  Future<void> _refresh() async {
    final settings = await GlyfBridge.sharedSettings();
    final contacts = await GlyfBridge.contactsStatus();
    final calendar = await GlyfBridge.calendarStatus();
    final google = await GlyfBridge.googleStatus();
    final nearby = await GlyfBridge.locationStatus();
    final up = await GlyfApi.healthy();
    final meter = await GlyfApi.meterStatus();
    final onboarding = await GlyfBridge.onboardingState();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _serverUp = up;
      _remaining = meter?.remaining;
      _serverPlan = meter?.plan;
      _perDay = meter?.perDay;
      _contactsOn = contacts['enabled'] == true;
      final booking = (settings['bookingLink'] as String?)?.trim() ?? '';
      // Contacts is counted under Search, where its switch lives.
      _connectedTools = [
        calendar['enabled'] == true,
        google['meet'] == true,
        booking.isNotEmpty,
      ].where((on) => on).length;
      _nearbyOn = nearby['enabled'] == true;
      _displayName = (onboarding['displayName'] as String?) ??
          Auth.identity().name ??
          'You';
    });
  }

  /// The Search row says which of its two switches is on.
  String get _searchStatus => switch ((_contactsOn, _nearbyOn)) {
        (true, true) => 'On',
        (true, false) => 'Contacts on',
        (false, true) => 'Nearby on',
        _ => '',
      };

  /// The server's plan when it answered (that is the one being enforced);
  /// the phone's own record only while offline.
  String get _plan => _serverPlan ??
      (_settings['plan'] as String?) ??
      (_settings['proUnlocked'] == true ? 'plus' : 'free');

  /// A day's runs on each plan, for when the server hasn't said (it sends
  /// the real number with what is left).
  int get _planRuns => switch (_plan) { 'max' => 400, 'plus' => 150, _ => 50 };
  /// Free counts its runs over a week; Plus and Max over a day.
  String get _period => _plan == 'plus' || _plan == 'max' ? 'today' : 'this week';

  /// Who you are, how you signed in and your plan, in one card: the name
  /// with Edit, the account under it, the plan, then Got a code? (a code is
  /// a plan too). Sign out is at the page's foot.
  Widget _identityCard() {
    final id = Auth.identity();
    final email = id.email ?? '';
    final provider = switch (id.provider) {
      'google' => 'Google',
      'apple' => 'Apple',
      _ => null,
    };
    Widget hairline() => Container(
        height: 1, margin: const EdgeInsets.only(left: 16), color: Glass.hairline);
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
          child: Row(children: [
            const KeycapGMark(size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Glass.ink, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Row(children: [
                  switch (id.provider) {
                    'google' => const GoogleG(size: 12),
                    'apple' => const Icon(Icons.apple, size: 14, color: Glass.ink),
                    _ => const Icon(Icons.person_outline_rounded, size: 14, color: Glass.inkSoft),
                  },
                  const SizedBox(width: 5),
                  Flexible(
                    child: Semantics(
                      identifier: 'profile:email',
                      child: Text(
                          email.isNotEmpty
                              ? email
                              : provider == null ? 'Signed in' : 'Signed in with $provider',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _editName,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Glass.ink,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('Edit',
                    style: TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        hairline(),
        Semantics(
          identifier: 'profile:plan',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _plan == 'max'
                ? null
                : () async {
                    await showPaywall(context);
                    _refresh();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        _plan == 'max'
                            ? 'Glyf Max'
                            : _plan == 'plus'
                                ? 'Glyf Plus'
                                : 'Free plan',
                        style: const TextStyle(
                            color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(
                        _remaining != null
                            ? '$_remaining of ${_perDay ?? _planRuns} runs left $_period'
                            : '$_planRuns runs ${_period == 'today' ? 'a day' : 'a week'}',
                        style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
                  ]),
                ),
                if (_plan != 'max')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      // Greyed until Plus and Max can be bought in the store.
                      color: _onSale ? Glass.ink : const Color(0xFFF1F2F5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(_onSale ? 'Upgrade' : 'Plans open soon',
                        style: TextStyle(
                            color: _onSale ? Colors.white : Glass.inkSoft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        ),
        hairline(),
        Semantics(
          identifier: 'profile:code',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CodeScreen()));
              _refresh();
            },
            child: const Padding(
              // 16 on the right lines its chevron up with the rows below.
              padding: EdgeInsets.fromLTRB(16, 12, 16, 13),
              child: Row(children: [
                Expanded(
                  child: Text('Got a code?',
                      style: TextStyle(
                          color: Glass.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right, color: Color(0xFFB9BEC7), size: 20),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _signOut() async {
    final email = Auth.identity().email;
    final go = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Sign out of Glyf?'),
        content: email == null || email.isEmpty ? null : Text('\n$email'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (go != true) return;
    await Auth.signOut();
    Telemetry.log('signed_out', {});
    widget.onRerunOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        children: [
          _identityCard(),
          const SizedBox(height: 16),
          _navCard(
            icon: Icons.keyboard_alt_outlined,
            title: 'Keyboard',
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const KeyboardScreen()));
              _refresh();
            },
          ),
          _navCard(
            icon: Icons.menu_book_outlined,
            title: 'Vocabulary',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VocabularyScreen())),
          ),
          _navCard(
            icon: Icons.lock_outline,
            title: 'Vault',
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VaultScreen()));
              _refresh();
            },
          ),
          Semantics(
            identifier: 'profile:search',
            button: true,
            child: _navCard(
              icon: Icons.search,
              title: 'Search',
              trailingText: _searchStatus,
              onTap: () async {
                await showSearchSheet(context, contacts: _contactsOn, nearby: _nearbyOn);
                _refresh();
              },
            ),
          ),
          _navCard(
            icon: Icons.cable_outlined,
            title: 'Connected tools',
            // Nothing on is nothing said, like the Search row.
            trailingText: _connectedTools > 0 ? '$_connectedTools active' : null,
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectedToolsScreen()));
              _refresh();
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: WalletFlow.enabled,
            builder: (context, on, _) => !on ? const SizedBox.shrink() : ValueListenableBuilder<WalletLink?>(
            valueListenable: WalletFlow.link,
            builder: (context, link, _) => _navCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet',
              trailingText: link == null ? 'Connect Phantom' : Sol.short(link.address),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (ctx) => const WalletScreen(),
              )),
            ),
          ),
          ),
          Semantics(
            identifier: 'profile:tour',
            button: true,
            child: _navCard(
              icon: Icons.chat_bubble_outline,
              title: 'Tour',
              onTap: _showTour,
            ),
          ),
          const SizedBox(height: 8),

          // Sign out and the privacy policy, plain text at the foot. Delete
          // account is not on the page: it is at the foot of Edit's sheet.
          Center(
            child: Semantics(
              identifier: 'profile:sign-out',
              button: true,
              child: TextButton(
                onPressed: _signOut,
                child: const Text('Sign out',
                    style: TextStyle(
                        color: Glass.danger, fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
              key: const Key('profile:privacy'),
              onPressed: () => GlyfBridge.openURL(privacyPolicyURL),
              child: const Text('Privacy policy',
                  style: TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ),
            TextButton(
              key: const Key('profile:terms'),
              onPressed: () => GlyfBridge.openURL(termsURL),
              child: const Text('Terms',
                  style: TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 14),

          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: _serverUp ? Glass.success : Glass.danger,
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(_serverUp ? 'Engine connected' : 'Engine offline',
                style: const TextStyle(color: Glass.inkSoft, fontSize: 12)),
          ]),
        ],
      ),
    );
  }

  Widget _navCard({
    required IconData icon,
    required String title,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: Glass.ink, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Glass.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          if (trailingText != null && trailingText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(trailingText,
                  style:
                      const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
            ),
          const Icon(Icons.chevron_right, color: Color(0xFFB9BEC7), size: 20),
        ]),
      ),
    );
  }

  /// The tour plays the website's chats on the real keyboard; a replay
  /// walks the setup steps again. Two jobs, one row: it asks which.
  Future<void> _showTour() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              // Stretch, or the card shrinks to its longest line.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            const Text('Tour',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            // One card of two rows, like the Search sheet's.
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _sheetRow(Icons.chat_bubble_outline, 'Take the tour', 'tour:chats',
                    () => Navigator.of(ctx).pop('tour')),
                Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 50),
                    color: Glass.hairline),
                _sheetRow(Icons.replay_outlined, 'Replay onboarding', 'tour:onboarding',
                    () => Navigator.of(ctx).pop('onboarding')),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    switch (pick) {
      case 'tour':
        // The app tour on Home, then the chats (the shell runs it).
        appTourRequests.value++;
      case 'onboarding':
        await _replayOnboarding();
    }
  }

  Widget _sheetRow(IconData icon, String title, String id, VoidCallback onTap) => Semantics(
        identifier: id,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(children: [
              Icon(icon, color: Glass.ink, size: 21),
              const SizedBox(width: 13),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFB9BEC7), size: 20),
            ]),
          ),
        ),
      );

  /// The steps again over Profile, with this person's own settings: nothing
  /// saved is lost and Close leaves from any step.
  Future<void> _replayOnboarding() async {
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => OnboardingFlow(replay: true, onDone: () => Navigator.of(ctx).pop()),
    ));
    _refresh();
  }

  /// The account card's Edit: the name. There is no Delete account in the
  /// app (Arpit, 2026-09-29: "remove delete account option, we dont want
  /// users to go idiot"); `Auth.deleteAccount` and the server's endpoint stay
  /// for when it comes back.
  Future<void> _editName() async {
    final name = (await showTextSheet(
      context,
      title: 'Your name',
      action: 'Save',
      initial: _displayName == 'You' ? '' : _displayName,
      maxLength: 24,
    ))
        ?.trim();
    if (name == null || name.isEmpty) return;
    final state = await GlyfBridge.onboardingState();
    state['displayName'] = name;
    await GlyfBridge.saveOnboardingState(state);
    try {
      await GlyfApi.setDisplayName(name);
    } catch (_) {}
    _refresh();
  }
}
