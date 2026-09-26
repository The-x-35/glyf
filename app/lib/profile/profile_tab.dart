import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoAlertDialog, CupertinoDialogAction, showCupertinoDialog;
import 'package:flutter/material.dart';

import '../core/auth.dart';
import 'connected_tools_screen.dart';
import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/text_sheet.dart';
import '../core/theme.dart';
import '../onboarding/demo_chat.dart';
import '../wallet/wallet_screen.dart';
import '../vault/vault_screen.dart';
import '../vocab/vocabulary_screen.dart';
import 'brand_marks.dart' show GoogleG;
import 'keyboard_screen.dart';
import 'paywall_sheet.dart';

/// Settings — one scrollable screen. Everything you can change about the
/// keyboard is here; there is no creator shelf and nothing to publish.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.onRerunOnboarding});
  final VoidCallback onRerunOnboarding;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _tone = {};
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
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Local state is cheap to re-read; the two server calls in here are
    // not, and every 5 s was 24 requests a minute from one idle screen.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final settings = await GlyfBridge.sharedSettings();
    final tone = await GlyfBridge.toneProfile();
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
      _tone = tone;
      _serverUp = up;
      _remaining = meter?.remaining;
      _serverPlan = meter?.plan;
      _perDay = meter?.perDay;
      _contactsOn = contacts['enabled'] == true;
      final booking = (settings['bookingLink'] as String?)?.trim() ?? '';
      _connectedTools = [
        _contactsOn,
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

  /// Turning a feature off is one tap on a row that reads like navigation,
  /// so it asks first, the way turning it on does.
  Future<bool> _confirmOff(String title, String body) async {
    final go = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text('\n$body'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn off')),
        ],
      ),
    );
    return go == true;
  }

  /// Gboard-style contacts search: explain, ask the OS, sync locally.
  Future<void> _toggleContacts() async {
    if (_contactsOn) {
      if (!await _confirmOff('Turn off Contacts search?',
          'The keyboard forgets the names, numbers and emails it kept.')) {
        return;
      }
      await GlyfBridge.contactsDisable();
      _refresh();
      return;
    }
    if (!mounted) return;
    final go = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Contacts search'),
        content: const Text(
          '\nLook up names, numbers and emails right from the keyboard. '
          'Contacts stay on this device. Nothing is uploaded.',
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn on')),
        ],
      ),
    );
    if (go != true) return;
    final res = await GlyfBridge.contactsEnable();
    if (!mounted) return;
    if (res['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${res['count']} contacts ready in the keyboard')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Allow contacts access in Settings to use this')));
    }
    _refresh();
  }

  /// "Near me" search: explain, ask the OS once, cache a coarse fix. The
  /// keyboard cannot ask for location itself, so the app owns this.
  Future<void> _toggleNearby() async {
    if (_nearbyOn) {
      if (!await _confirmOff('Turn off Nearby search?',
          'The keyboard forgets where you are, so "near me" goes back to plain search.')) {
        return;
      }
      await GlyfBridge.locationDisable();
      _refresh();
      return;
    }
    if (!mounted) return;
    final go = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Nearby search'),
        content: const Text(
          '\nSo “coffee near me” finds coffee near you, and the keyboard can '
          'answer local things like sunset and weather.\n\n'
          'Approximate only, kept on this device, never stored on our servers.',
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn on')),
        ],
      ),
    );
    if (go != true) return;
    final res = await GlyfBridge.locationEnable();
    if (!mounted) return;
    final message = res['ok'] == true
        ? 'Nearby search is on'
        : switch (res['error']) {
            'denied' => 'Allow location access in Settings to use this',
            'nofix' => 'No recent location yet. Open Maps once, then retry.',
            _ => 'Location isn\u2019t available on this device',
          };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    _refresh();
  }

  /// The server's plan when it answered (that is the one being enforced);
  /// the phone's own record only while offline.
  String get _plan => _serverPlan ??
      (_settings['plan'] as String?) ??
      (_settings['proUnlocked'] == true ? 'plus' : 'free');

  /// A day's runs on each plan, for when the server hasn't said (it sends
  /// the real number with what is left).
  int get _planRuns => switch (_plan) { 'max' => 400, 'plus' => 150, _ => 20 };

  /// Who is signed in, and Sign out beside it: under the name, where it is
  /// seen without scrolling.
  Widget _account() {
    final id = Auth.identity();
    final email = id.email ?? '';
    final provider = switch (id.provider) {
      'google' => 'Google',
      'apple' => 'Apple',
      _ => null,
    };
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Glass.bg, shape: BoxShape.circle),
          child: switch (id.provider) {
            'google' => const GoogleG(size: 18),
            'apple' => const Icon(Icons.apple, size: 21, color: Glass.ink),
            _ => const Icon(Icons.person_outline_rounded, size: 20, color: Glass.ink),
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(provider == null ? 'Signed in' : 'Signed in with $provider',
                style: const TextStyle(
                    color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            if (email.isNotEmpty)
              Semantics(
                identifier: 'profile:email',
                child: Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        Semantics(
          identifier: 'profile:sign-out',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _signOut,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Glass.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text('Sign out',
                  style: TextStyle(
                      color: Glass.danger,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
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

  /// App Store rule 5.1.1(v): an account made in the app can be deleted in
  /// the app. What stays on this phone (vault, notes, keyboard settings)
  /// stays until the app is deleted.
  Future<void> _deleteAccount() async {
    final email = Auth.identity().email;
    final go = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete your Glyf account?'),
        content: Text('${email == null || email.isEmpty ? '' : '\n$email\n\n'}'
            'Your account and what Glyf keeps for it are deleted for good. '
            'Your vault and notes stay on this phone.'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (go != true) return;
    final done = await Auth.deleteAccount();
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't reach Glyf. Try again in a moment")));
      return;
    }
    Telemetry.log('account_deleted', {});
    widget.onRerunOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        children: [
          // Identity
          Row(children: [
            const KeycapGMark(size: 62),
            const SizedBox(width: 16),
            Expanded(
              child: Text(_displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Glass.ink,
                      fontSize: 23,
                      fontWeight: FontWeight.w800)),
            ),
            GestureDetector(
              onTap: _editName,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: Glass.ink,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text('Edit',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Account
          _account(),
          const SizedBox(height: 12),

          // Plan
          Semantics(
            identifier: 'profile:plan',
            button: true,
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              onTap: _plan == 'max'
                  ? null
                  : () async {
                      await showPaywall(context);
                      _refresh();
                    },
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _plan == 'max'
                                ? 'Glyf Max'
                                : _plan == 'plus'
                                    ? 'Glyf Plus'
                                    : 'Free plan',
                            style: const TextStyle(
                                color: Glass.ink,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700)),
                        Text(
                            _remaining != null
                                ? '$_remaining of ${_perDay ?? _planRuns} runs left today'
                                : '$_planRuns runs a day',
                            style: const TextStyle(
                                color: Glass.inkSoft, fontSize: 12.5)),
                      ]),
                ),
                if (_plan != 'max')
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      // Greyed until Plus and Max can be bought in the store.
                      color: plansOnSale ? Glass.ink : const Color(0xFFF1F2F5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                        !plansOnSale
                            ? 'Pro coming soon'
                            : _plan == 'plus' ? 'Upgrade' : 'Go Pro',
                        style: TextStyle(
                            color: plansOnSale ? Colors.white : Glass.inkSoft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 22),

          _groupLabel('Keyboard'),
          _navCard(
            icon: Icons.keyboard_alt_outlined,
            title: 'Keyboard',
            trailingText: 'Look, typing, feel',
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
          const SizedBox(height: 18),
          _groupLabel('You'),
          _navCard(
            icon: Icons.person_search_outlined,
            title: 'Contacts search',
            trailingText: _contactsOn ? 'On' : '',
            onTap: _toggleContacts,
          ),
          _navCard(
            icon: Icons.near_me_outlined,
            title: 'Nearby search',
            trailingText: _nearbyOn ? 'On' : '',
            onTap: _toggleNearby,
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
          _navCard(
            icon: Icons.cable_outlined,
            title: 'Connected tools',
            trailingText: '$_connectedTools active',
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectedToolsScreen()));
              _refresh();
            },
          ),
          _navCard(
            icon: Icons.auto_fix_high_outlined,
            title: 'Tone profile',
            trailingText:
                (_tone['hint'] as String?)?.isNotEmpty == true ? 'Active' : '',
            onTap: _showTone,
          ),
          const SizedBox(height: 18),
          _groupLabel('More'),
          _navCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Wallet',
            trailingText: 'Private sends',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (ctx) => const WalletScreen(),
            )),
          ),
          _navCard(
            icon: Icons.chat_bubble_outline,
            title: 'Take the tour',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (ctx) => DemoChat(onDone: () => Navigator.of(ctx).pop()),
            )),
          ),
          _navCard(
            icon: Icons.replay_outlined,
            title: 'Replay onboarding',
            onTap: widget.onRerunOnboarding,
          ),
          if (Auth.signedIn)
            Center(
              child: TextButton(
                key: const Key('profile:delete-account'),
                onPressed: _deleteAccount,
                child: const Text('Delete account',
                    style: TextStyle(
                        color: Glass.danger,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          Center(
            child: TextButton(
              key: const Key('profile:privacy'),
              onPressed: () => GlyfBridge.openURL(privacyPolicyURL),
              child: const Text('Privacy policy',
                  style: TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ),
          ),
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

  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(
                color: Glass.inkSoft,
                fontSize: 13.5,
                fontWeight: FontWeight.w600)),
      );

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

  Future<void> _showTone() async {
    final hint = (_tone['hint'] as String?) ?? '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              // Stretch, or the sheet shrinks to its longest line and floats
              // in the middle of the screen with gaps on either side.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            const Text('Tone profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(hint.isNotEmpty ? hint : 'Learning from your edits',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Glass.inkSoft, fontSize: 14, height: 1.5)),
            const SizedBox(height: 8),
            const Text('On this device only. Never your words.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB6BAC3), fontSize: 12)),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () async {
                await GlyfBridge.toneReset();
                Telemetry.log('tone_reset');
                if (ctx.mounted) Navigator.of(ctx).pop();
                _refresh();
              },
              child: const Text('Reset',
                  style: TextStyle(color: Color(0xFFC03A2E), fontSize: 14)),
            ),
          ]),
        ),
      ),
    );
  }

}
