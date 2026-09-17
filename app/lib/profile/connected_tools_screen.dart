import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../wallet/wallet_screen.dart';
import 'brand_marks.dart';

/// What Glyf reaches beyond the keyboard: private payments, the phone's own
/// calendar and contacts, and the apps coming next.
class ConnectedToolsScreen extends StatefulWidget {
  const ConnectedToolsScreen({super.key});

  @override
  State<ConnectedToolsScreen> createState() => _ConnectedToolsScreenState();
}

class _ConnectedToolsScreenState extends State<ConnectedToolsScreen> {
  bool _calendar = false;
  bool _contacts = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cal = await GlyfBridge.calendarStatus();
    final contacts = await GlyfBridge.contactsStatus();
    if (!mounted) return;
    setState(() {
      _calendar = cal['enabled'] == true;
      _contacts = contacts['enabled'] == true;
    });
  }

  Future<void> _toggleCalendar(bool on) async {
    if (!on) {
      await GlyfBridge.calendarDisable();
      setState(() => _calendar = false);
      Telemetry.log('tool_disconnected', {'tool': 'calendar'});
      return;
    }
    final res = await GlyfBridge.calendarEnable();
    if (!mounted) return;
    setState(() {
      _calendar = res['ok'] == true;
      _note = res['ok'] == true ? null : 'Allow Calendar for Glyf in Settings to use it in the keyboard.';
    });
    Telemetry.log('tool_connected', {'tool': 'calendar', 'ok': _calendar});
  }

  Future<void> _toggleContacts(bool on) async {
    if (!on) {
      await GlyfBridge.contactsDisable();
      setState(() => _contacts = false);
      Telemetry.log('tool_disconnected', {'tool': 'contacts'});
      return;
    }
    final res = await GlyfBridge.contactsEnable();
    if (!mounted) return;
    setState(() {
      _contacts = res['ok'] == true;
      _note = res['ok'] == true ? null : 'Allow Contacts for Glyf in Settings to search them from the keyboard.';
    });
    Telemetry.log('tool_connected', {'tool': 'contacts', 'ok': _contacts});
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
            trailing: _switch(_calendar, _toggleCalendar, 'tools:calendar'),
          ),
          const SizedBox(height: 12),
          _toolCard(
            brand: 'contacts',
            title: 'Contacts',
            useCase: 'Find a number or email without leaving the keyboard.',
            trailing: _switch(_contacts, _toggleContacts, 'tools:contacts'),
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
            ('gcal', 'Google Calendar', 'Drop a meeting link and a time in one tap.'),
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
          'Someone drops a Solana address in a chat: tap Pay on the keyboard and send USDC. Nobody onchain can see who paid.',
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

  Widget _soon() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFFF1F2F5), borderRadius: BorderRadius.circular(20)),
        child: const Text('Soon', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
      );
}
