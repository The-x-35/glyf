import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../wallet/wallet_screen.dart';
import 'brand_marks.dart';

/// What Glyf reaches beyond the keyboard: private payments, the phone's
/// calendar, Google Meet, a booking page, contacts, and the apps coming next.
/// Onboarding asks for the calendar and Google Meet; this is where someone
/// who said "Not now" turns them on later.
class ConnectedToolsScreen extends StatefulWidget {
  const ConnectedToolsScreen({super.key});

  @override
  State<ConnectedToolsScreen> createState() => _ConnectedToolsScreenState();
}

class _ConnectedToolsScreenState extends State<ConnectedToolsScreen> {
  bool _calendar = false;
  /// Google Calendar and Meet: `connected`, `email`, `calendar`, `meet`.
  Map<String, dynamic> _google = const {'connected': false};
  /// Google's page is open, or the grant is being taken back.
  bool _googleBusy = false;
  /// The person's Cal.com or Calendly page, for the keyboard's Book a time.
  String? _booking;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cal = await GlyfBridge.calendarStatus();
    final google = await GlyfBridge.googleStatus();
    final shared = await GlyfBridge.sharedSettings();
    if (!mounted) return;
    setState(() {
      _calendar = _calendarOn(cal);
      _google = google;
      final link = (shared['bookingLink'] as String?)?.trim() ?? '';
      _booking = link.isEmpty ? null : link;
    });
  }

  /// On when the keyboard can use it: turned on, and still allowed.
  static bool _calendarOn(Map<String, dynamic> status) =>
      status['enabled'] == true && (status['permission'] == 'granted' || status['permission'] == 'writeOnly');

  /// The phone asks once; after a refusal only Settings can allow it, and
  /// taking it back is Settings' too, so there is no off here.
  Future<void> _enableCalendar() async {
    final res = await GlyfBridge.calendarEnable();
    final status = await GlyfBridge.calendarStatus();
    if (!mounted) return;
    setState(() {
      _calendar = res['ok'] == true && _calendarOn(status);
      _note = _calendar ? null : 'Calendar is off for Glyf. You can allow it in Settings.';
    });
    Telemetry.log('tool_connected', {'tool': 'calendar', 'ok': _calendar});
  }

  /// Meet links, and events in Google Calendar whose guests Google emails.
  /// The same Google page onboarding opens; off takes the grant back from
  /// Google too.
  Future<void> _toggleGoogle(bool on) async {
    if (_googleBusy) return;
    setState(() => _googleBusy = true);
    if (!on) {
      await GlyfBridge.googleDisconnect();
      if (!mounted) return;
      setState(() {
        _googleBusy = false;
        _google = const {'connected': false};
      });
      Telemetry.log('tool_disconnected', {'tool': 'google'});
      return;
    }
    final error = await Auth.connectGoogle();
    final status = await GlyfBridge.googleStatus();
    if (!mounted) return;
    setState(() {
      _googleBusy = false;
      _google = status;
      _note = error;
    });
    Telemetry.log('tool_connected', {'tool': 'google', 'ok': status['meet'] == true});
  }

  /// Which service a booking link belongs to ("calcom", "calendly"), or null
  /// when it is neither or names no page.
  static String? bookingProvider(String link) {
    final s = link.trim().toLowerCase()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '');
    final parts = s.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final host = parts.first;
    if (host == 'calendly.com') return 'calendly';
    if (host == 'cal.com' || host.endsWith('.cal.com')) return 'calcom';
    return null;
  }

  Future<void> _editBooking() async {
    final field = TextEditingController(text: _booking ?? '');
    String? error;
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 36, height: 5,
                decoration: BoxDecoration(color: const Color(0x26000000), borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Booking link', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Glass.ink)),
            const SizedBox(height: 14),
            Semantics(
              identifier: 'booking:field',
              child: TextField(
                controller: field,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'cal.com/you or calendly.com/you',
                  errorText: error,
                  filled: true,
                  fillColor: const Color(0xFFF2F2F7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              if (_booking != null)
                Semantics(
                  identifier: 'booking:remove',
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, ''),
                    child: const Text('Remove', style: TextStyle(color: Color(0xFFFF3B30), fontSize: 15)),
                  ),
                ),
              const Spacer(),
              Semantics(
                identifier: 'booking:save',
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Glass.ink, minimumSize: const Size(96, 44)),
                  onPressed: () {
                    final v = field.text.trim();
                    if (bookingProvider(v) == null) {
                      setSheet(() => error = 'That isn’t a Cal.com or Calendly link');
                      return;
                    }
                    Navigator.pop(ctx, v);
                  },
                  child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    // The sheet's route lets go of the field a beat after popping;
    // disposing under it red-screens.
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    if (saved == null || !mounted) return;
    final link = saved.isEmpty ? null : saved;
    await GlyfBridge.updateSharedSettings((s) {
      if (link == null) {
        s.remove('bookingLink');
      } else {
        s['bookingLink'] = link;
      }
      return s;
    });
    if (!mounted) return;
    setState(() => _booking = link);
    Telemetry.log(link == null ? 'tool_disconnected' : 'tool_connected', {'tool': 'booking'});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Connected tools', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          _magicBlock(),
          const SizedBox(height: 12),
          _toolCard(
            brand: 'calendar',
            title: 'Calendar',
            useCase: 'Share an event, or when you’re free, straight into a chat.',
            trailing: _calendar ? _onBadge('tools:calendar') : _actionPill('Turn on', 'tools:calendar', _enableCalendar),
          ),
          const SizedBox(height: 12),
          _toolCard(
            brand: 'meet',
            title: 'Google Meet',
            useCase: _google['meet'] == true
                ? (_google['email'] as String? ?? 'Connected')
                : 'Send a Meet link or a calendar invite from the keyboard.',
            trailing: _switch(_google['meet'] == true, _toggleGoogle, 'tools:google'),
          ),
          const SizedBox(height: 12),
          _toolCard(
            brand: _booking == null ? 'booking' : (bookingProvider(_booking!) ?? 'booking'),
            title: 'Booking link',
            useCase: _booking ?? 'Cal.com or Calendly: send times people can book, from the keyboard.',
            trailing: _actionPill(_booking == null ? 'Add' : 'Edit', 'tools:booking', _editBooking),
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(_note!, style: const TextStyle(fontSize: 13, color: Glass.inkSoft)),
            ),
          const SizedBox(height: 26),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Coming soon',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
          ),
          for (final (brand, title, useCase) in const [
            ('gmail', 'Gmail', 'Answer an email from whatever chat you’re in.'),
            ('notion', 'Notion', 'Share a page or add a task while you type.'),
            ('slack', 'Slack', 'Send a thread to a friend without switching apps.'),
            ('spotify', 'Spotify', 'Send the song you’re playing right now.'),
          ]) ...[
            _toolCard(brand: brand, title: title, useCase: useCase, trailing: _soon()),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _magicBlock() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15131C), Color(0xFF2A1F4A), Color(0xFF4B2A86)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const BrandMark('magicblock', size: 46),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Private payments',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('by MagicBlock', style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 13.5)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x3334C759),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Live', style: TextStyle(color: Color(0xFF5BE38A), fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 14),
        const Text(
          'Someone drops a Solana address in a chat: tap Send on the keyboard and Phantom signs. Send privately, and nobody onchain can see who paid.',
          style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 14, height: 1.35),
        ),
        const SizedBox(height: 14),
        Semantics(
          identifier: 'tools:wallet',
          button: true,
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(21)),
              child: const Text('Open wallet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _toolCard({required String brand, required String title, required String useCase, required Widget trailing}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Glass.hairline),
      ),
      child: Row(children: [
        BrandMark(brand, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Glass.ink)),
            const SizedBox(height: 2),
            Text(useCase, style: const TextStyle(fontSize: 13, height: 1.3, color: Glass.inkSoft)),
          ]),
        ),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }

  Widget _switch(bool value, ValueChanged<bool> onChanged, String id) => Semantics(
        identifier: id,
        child: CupertinoSwitch(value: value, activeTrackColor: Glass.ink, onChanged: onChanged),
      );

  Widget _actionPill(String label, String id, VoidCallback onTap) => Semantics(
        identifier: id,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: Glass.ink, borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      );

  Widget _onBadge(String id) => Semantics(
        identifier: id,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(color: const Color(0x1F1FA968), borderRadius: BorderRadius.circular(20)),
          child: const Text('On', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Glass.success)),
        ),
      );

  Widget _soon() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFFF1F2F5), borderRadius: BorderRadius.circular(20)),
        child: const Text('Soon', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
      );
}
