import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoAlertDialog, CupertinoDialogAction, showCupertinoDialog;
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../notes/notes_screen.dart';
import '../vault/vault_screen.dart';
import '../vocab/vocabulary_screen.dart';
import 'keyboard_settings_sheet.dart';
import 'paywall_sheet.dart';
import 'themes_screen.dart';

/// Profile — identity up top, then Creator and Settings groups.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.onRerunOnboarding});
  final VoidCallback onRerunOnboarding;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _tone = {};
  Map<String, dynamic> _creator = {};
  String _displayName = 'You';
  bool _serverUp = false;
  int? _remaining;
  int _connectedTools = 1; // the demo calendar
  bool _contactsOn = false;
  bool _nearbyOn = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
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
    final nearby = await GlyfBridge.locationStatus();
    final up = await GlyfApi.healthy();
    final remaining =
        settings['proUnlocked'] == true ? null : await GlyfApi.meterRemaining();
    Map<String, dynamic> creator = _creator;
    try {
      creator = await GlyfApi.creatorStats();
    } catch (_) {}
    final onboarding = await GlyfBridge.onboardingState();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _tone = tone;
      _serverUp = up;
      _remaining = remaining;
      _creator = creator;
      _contactsOn = contacts['enabled'] == true;
      _nearbyOn = nearby['enabled'] == true;
      _displayName = (onboarding['displayName'] as String?) ?? 'You';
    });
  }

  /// Gboard-style contacts search: explain, ask the OS, sync locally.
  Future<void> _toggleContacts() async {
    if (_contactsOn) {
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
          'Contacts stay on this device — nothing is uploaded.',
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
            'nofix' => 'No recent location yet — open Maps once, then retry',
            _ => 'Location isn\u2019t available on this device',
          };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    _refresh();
  }

  String get _plan => (_settings['plan'] as String?) ??
      (_settings['proUnlocked'] == true ? 'plus' : 'free');
  String get _uid =>
      ((_settings['deviceId'] as String?) ?? '').replaceAll('-', '')
          .padRight(8, '0')
          .substring(0, 8)
          .toUpperCase();

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
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_displayName,
                    style: const TextStyle(
                        color: Glass.ink,
                        fontSize: 23,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Glass.hairline),
                  ),
                  child: Text('UID $_uid',
                      style: const TextStyle(
                          color: Glass.inkSoft, fontSize: 11.5)),
                ),
              ]),
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
          const SizedBox(height: 22),

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
                            _plan == 'max'
                                ? 'Unlimited runs'
                                : _plan == 'plus'
                                    ? '400 runs a day'
                                    : _remaining != null
                                        ? '$_remaining runs left today'
                                        : '40 runs a day',
                            style: const TextStyle(
                                color: Glass.inkSoft, fontSize: 12.5)),
                      ]),
                ),
                if (_plan != 'max')
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Glass.ink,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(_plan == 'plus' ? 'Upgrade' : 'Go Pro',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 22),

          _groupLabel('Creator'),
          _navCard(
            icon: Icons.auto_awesome_outlined,
            title: 'My Glyfs',
            trailingText: '${_creator['glyfs'] ?? 0} created',
            onTap: () => Telemetry.log('profile_myglyfs'),
          ),
          _navCard(
            icon: Icons.workspace_premium_outlined,
            title: 'Creator stats',
            trailingText: '${_creator['installs'] ?? 0} installs',
            onTap: () {},
          ),
          const SizedBox(height: 18),

          _groupLabel('Settings'),
          _navCard(
            icon: Icons.keyboard_alt_outlined,
            title: 'Keyboard',
            onTap: () => showKeyboardSettings(context),
          ),
          _navCard(
            icon: Icons.menu_book_outlined,
            title: 'Vocabulary',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VocabularyScreen())),
          ),
          _navCard(
            icon: Icons.palette_outlined,
            title: 'Themes',
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ThemesScreen()));
              _refresh();
            },
          ),
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
            icon: Icons.badge_outlined,
            title: 'Your info & shorthand',
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VaultScreen()));
              _refresh();
            },
          ),
          _navCard(
            icon: Icons.sticky_note_2_outlined,
            title: 'Notes',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotesScreen())),
          ),
          _navCard(
            icon: Icons.cable_outlined,
            title: 'Connected tools',
            trailingText: '$_connectedTools active',
            onTap: _showConnectors,
          ),
          _navCard(
            icon: Icons.auto_fix_high_outlined,
            title: 'Tone profile',
            trailingText:
                (_tone['hint'] as String?)?.isNotEmpty == true ? 'Active' : '',
            onTap: _showTone,
          ),
          _navCard(
            icon: Icons.replay_outlined,
            title: 'Replay onboarding',
            onTap: widget.onRerunOnboarding,
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
    final ctrl = TextEditingController(
        text: _displayName == 'You' ? '' : _displayName);
    final name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Your name',
              style: TextStyle(
                  color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 24,
            style: const TextStyle(color: Glass.ink, fontSize: 16),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF7F8FA),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          PillButton(
              label: 'Save',
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim())),
          const SizedBox(height: 4),
        ]),
      ),
    );
    ctrl.dispose();
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Tone profile',
                style: TextStyle(
                    color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(hint.isNotEmpty ? hint : 'Learning from your edits',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Glass.inkSoft, fontSize: 14, height: 1.5)),
            const SizedBox(height: 8),
            const Text('On this device only. Never your words.',
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

  Future<void> _showConnectors() async {
    Map<String, dynamic>? status;
    try {
      status = await GlyfApi.connectorsStatus();
    } catch (_) {}
    if (!mounted) return;
    final providers =
        (status?['providers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final mock = status?['mock'] as Map<String, dynamic>?;
    _connectedTools = (mock != null ? 1 : 0) +
        providers.where((p) => p['connected'] == true).length;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Connected tools',
                style: TextStyle(
                    color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (status == null)
              const Text('Engine offline',
                  style: TextStyle(color: Glass.inkSoft, fontSize: 13)),
            if (mock != null)
              _connectorRow(
                  label: mock['label'] as String? ?? 'Demo Calendar',
                  detail: 'Connected',
                  ok: true),
            for (final p in providers)
              _connectorRow(
                label: p['label'] as String? ?? (p['id'] as String),
                detail: p['connected'] == true
                    ? (p['email'] as String? ?? 'Connected')
                    : p['configured'] == true
                        ? 'Ready to connect'
                        : 'Coming soon',
                ok: p['connected'] == true,
                action: p['id'] != 'google'
                    ? null
                    : p['connected'] == true
                        ? ('Disconnect', () async {
                            await GlyfApi.disconnect('google');
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            _refresh();
                          })
                        : p['configured'] == true
                            ? ('Connect', () async {
                                try {
                                  final url = await GlyfApi.googleStartUrl(
                                      ['calendar', 'gmail', 'meet']);
                                  await GlyfBridge.openURL(url);
                                } catch (_) {}
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              })
                            : null,
              ),
            const SizedBox(height: 6),
          ]),
        ),
      ),
    );
  }

  Widget _connectorRow({
    required String label,
    required String detail,
    required bool ok,
    (String, VoidCallback)? action,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
              color: ok ? Glass.success : const Color(0xFFD9DCE2),
              shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    color: Glass.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600)),
            Text(detail,
                style: const TextStyle(color: Glass.inkSoft, fontSize: 11.5)),
          ]),
        ),
        if (action != null)
          TextButton(
            onPressed: action.$2,
            child: Text(action.$1,
                style: const TextStyle(
                    color: Glass.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}
