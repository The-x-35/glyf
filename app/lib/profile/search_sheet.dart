import 'package:flutter/cupertino.dart'
    show CupertinoAlertDialog, CupertinoDialogAction, CupertinoSwitch, showCupertinoDialog;
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/theme.dart';

/// Contacts search and Nearby search, the two switches behind Profile's
/// Search row (each used to be a row of its own). A keyboard can't ask the
/// phone for contacts or location, so the app asks here and keeps what the
/// keyboard reads: a contacts index and a rough fix, both on the phone.
///
/// [contacts] and [nearby] are what Profile last saw, so the switches don't
/// flick from off while the sheet reads them again.
Future<void> showSearchSheet(BuildContext context, {bool contacts = false, bool nearby = false}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (_) => _SearchSheet(contacts: contacts, nearby: nearby),
    );

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.contacts, required this.nearby});
  final bool contacts;
  final bool nearby;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late bool _contacts = widget.contacts;
  late bool _nearby = widget.nearby;

  /// What the last switch came to. It is said here because a snack bar
  /// would open under the sheet, out of sight.
  String? _note;

  /// A switch's dialog, the phone's prompt or the contacts sync is under
  /// way: a second tap would ask all over again.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contacts = await GlyfBridge.contactsStatus();
    final nearby = await GlyfBridge.locationStatus();
    if (!mounted) return;
    setState(() {
      _contacts = contacts['enabled'] == true;
      _nearby = nearby['enabled'] == true;
    });
  }

  Future<void> _once(Future<void> Function() flow) async {
    if (_busy) return;
    _busy = true;
    try {
      await flow();
    } finally {
      _busy = false;
    }
  }

  /// Off forgets what the keyboard kept (the contacts, where you are), so
  /// it asks first, the way on does.
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
    if (_contacts) {
      if (!await _confirmOff('Turn off Contacts search?',
          'The keyboard forgets the names, numbers and emails it kept.')) {
        return;
      }
      await GlyfBridge.contactsDisable();
      if (mounted) setState(() => _note = null);
      await _load();
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
    setState(() => _note = res['ok'] == true
        ? '${res['count']} contacts ready in the keyboard'
        : 'Allow contacts access in Settings to use this');
    await _load();
  }

  /// "Near me" search: explain, ask the OS once, cache a coarse fix. The
  /// keyboard cannot ask for location itself, so the app owns this.
  Future<void> _toggleNearby() async {
    if (_nearby) {
      if (!await _confirmOff('Turn off Nearby search?',
          'The keyboard forgets where you are, so "near me" goes back to plain search.')) {
        return;
      }
      await GlyfBridge.locationDisable();
      if (mounted) setState(() => _note = null);
      await _load();
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
    setState(() => _note = res['ok'] == true
        ? 'Nearby search is on'
        : switch (res['error']) {
            'denied' => 'Allow location access in Settings to use this',
            'nofix' => 'No recent location yet. Open Maps once, then retry.',
            _ => 'Location isn’t available on this device',
          });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // Stretch, or the card shrinks to its longest line.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Search',
                textAlign: TextAlign.center,
                style: TextStyle(color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _row(Icons.person_search_outlined, 'Contacts', _contacts, _toggleContacts, 'search:contacts'),
                Container(height: 1, margin: const EdgeInsets.only(left: 50), color: Glass.hairline),
                _row(Icons.near_me_outlined, 'Nearby', _nearby, _toggleNearby, 'search:nearby'),
              ]),
            ),
            if (_note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Text(_note!, style: const TextStyle(fontSize: 13, color: Glass.inkSoft)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String title, bool on, Future<void> Function() toggle, String id) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
        child: Row(children: [
          Icon(icon, color: Glass.ink, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Text(title,
                style: const TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Semantics(
            identifier: id,
            child: CupertinoSwitch(
              value: on,
              activeTrackColor: Glass.ink,
              onChanged: (_) => _once(toggle),
            ),
          ),
        ]),
      );
}
