import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// The website's guided chat, played on the real keyboard.
///
/// tryglyf.com walks a visitor through Glyf by handing them a thread and a
/// job: someone asks for your address, someone asks you to split a bill.
/// This is that, except the keyboard under it is the one they just enabled,
/// so the muscle memory they build here is the muscle memory they keep.
class DemoChat extends StatefulWidget {
  const DemoChat({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<DemoChat> createState() => _DemoChatState();
}

/// One person, one thing they want, one way Glyf gets it done.
class _Level {
  const _Level({
    required this.id,
    required this.name,
    required this.avatar,
    required this.tint,
    required this.tag,
    required this.them,
    required this.coach,
    required this.how,
    required this.goal,
    required this.reply,
    required this.tapback,
    this.demoText,
  });

  final String id;
  final String name;
  final String avatar;
  final Color tint;
  final String tag;
  final List<String> them;
  /// What to do, in the fewest words that still say it.
  final String coach;
  final String how;
  final bool Function(String sent, _VaultPeek vault) goal;
  final List<String> reply;
  final String tapback;
  /// What "Show me" types, when someone would rather watch than try.
  final String? demoText;
}

/// What the vault holds, so a level can check the real answer went out.
class _VaultPeek {
  const _VaultPeek(this.values);
  final List<String> values;
  bool matched(String sent) {
    final t = sent.toLowerCase();
    return values.any((v) => v.length > 3 && t.contains(v.toLowerCase()));
  }
}

const _polite = [
  'absolutely', 'sure thing', 'of course', 'happy to', 'on it',
  'certainly', 'will do', 'sorry', 'please', 'thanks',
];

final _levels = <_Level>[
  _Level(
    id: 'math',
    name: 'Zoya',
    avatar: '🍕',
    tint: const Color(0xFFFF9F0A),
    tag: 'Maths, mid-sentence',
    them: ['dinner was 3480 for the four of us 😭', 'how much do i owe you?'],
    coach: 'Type 3480/4 and tap the answer',
    how: 'Glyf does the sum in the strip. Tap it and the answer lands in '
        'the message.',
    goal: (sent, _) => sent.contains('870'),
    reply: ['perfect, sending now 🙏', 'you\'re the best'],
    tapback: '🙏',
    demoText: '3480/4 = 870',
  ),
  _Level(
    id: 'vault',
    name: 'Mumma',
    avatar: '🎁',
    tint: const Color(0xFFFF6FAE),
    tag: 'Never type it again',
    them: ['hi beta 🎉', 'sending you something', 'what\'s your address?'],
    coach: 'Hold S, or tap the card icon',
    how: 'Everything you saved lives on the keyboard. Nothing leaves your '
        'phone until you tap it.',
    goal: (sent, vault) => vault.matched(sent) || sent.trim().length > 12,
    reply: ['got it beta ❤️', 'it\'ll be there by friday'],
    tapback: '❤️',
  ),
  _Level(
    id: 'ai',
    name: 'Neha',
    avatar: '💼',
    tint: const Color(0xFF5E5CE6),
    tag: 'AI, without leaving',
    them: ['hey, the deck for tomorrow', 'can you get it to me before 6?'],
    coach: 'Type roughly, then hold the space bar',
    how: 'Hold space and Glyf rewrites what you typed. Keep it or don\'t.',
    goal: (sent, _) {
      final t = sent.toLowerCase();
      return _polite.any(t.contains) && sent.trim().length > 18;
    },
    reply: ['amazing, thank you!', 'see you at the review 🙌'],
    tapback: '👍',
    demoText: 'Absolutely, I\'ll send the deck across before 6.',
  ),
  _Level(
    id: 'emoji',
    name: 'Rohan',
    avatar: '🏏',
    tint: const Color(0xFF32D583),
    tag: 'The rest of it',
    them: ['we won 🏆', 'still can\'t believe that last over'],
    coach: 'Send something with an emoji',
    how: 'Emoji is the key beside 123, where iOS keeps it. The strip holds '
        'search, clipboard, vault and translate.',
    goal: (sent, _) => sent.runes.any((r) => r > 0x203F),
    reply: ['hahaha same 😭', 'next match you\'re coming'],
    tapback: '😂',
    demoText: 'what a finish 🔥',
  ),
];

class _Msg {
  _Msg(this.text, {required this.mine});
  final String text;
  final bool mine;
  /// Set when the other side reacts to what you sent.
  String? tapback;
}

class _DemoChatState extends State<DemoChat> {
  int _level = 0;
  final _msgs = <_Msg>[];
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _busy = false;
  bool _coachUp = false;
  _VaultPeek _vault = const _VaultPeek([]);
  Timer? _typing;

  @override
  void initState() {
    super.initState();
    Telemetry.log('demo_start', {});
    _loadVault();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLevel());
  }

  @override
  void dispose() {
    _typing?.cancel();
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadVault() async {
    final raw = await GlyfBridge.vaultList();
    if (raw == null || !mounted) return;
    try {
      final json = jsonDecode(raw);
      final fields = (json is Map ? json['fields'] : null) as List? ?? const [];
      setState(() => _vault = _VaultPeek([
            for (final f in fields)
              if (f is Map && f['value'] is String) f['value'] as String,
          ]));
    } catch (_) {
      // A vault we cannot read just means this level accepts any answer.
    }
  }

  _Level get _current => _levels[_level];

  Future<void> _runLevel() async {
    setState(() {
      _msgs.clear();
      _coachUp = false;
      _busy = true;
    });
    for (final line in _current.them) {
      await Future.delayed(const Duration(milliseconds: 620));
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(line, mine: false)));
      _toBottom();
    }
    await Future.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _coachUp = true;
    });
    _focus.requestFocus();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _msgs.add(_Msg(text, mine: true));
      _coachUp = false;
      _busy = true;
    });
    _toBottom();

    final done = _current.goal(text, _vault);
    Telemetry.log('demo_send', {'level': _current.id, 'done': done});
    await Future.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;
    if (!done) {
      setState(() {
        _msgs.add(_Msg('hmm, try again? 🙈', mine: false));
        _coachUp = true;
        _busy = false;
      });
      _toBottom();
      return;
    }
    setState(() => _msgs.last.tapback = _current.tapback);
    for (final line in _current.reply) {
      await Future.delayed(const Duration(milliseconds: 560));
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(line, mine: false)));
      _toBottom();
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    if (_level >= _levels.length - 1) {
      Telemetry.log('demo_complete', {});
      widget.onDone();
      return;
    }
    setState(() {
      _level++;
      _busy = false;
    });
    _runLevel();
  }

  void _showMe() {
    final text = _current.demoText;
    if (text == null) return;
    Telemetry.log('demo_show_me', {'level': _current.id});
    _typing?.cancel();
    _controller.clear();
    var i = 0;
    _typing = Timer.periodic(const Duration(milliseconds: 26), (t) {
      if (!mounted || i >= text.length) {
        t.cancel();
        return;
      }
      i++;
      _controller.text = text.substring(0, i);
      _controller.selection = TextSelection.collapsed(offset: i);
    });
  }

  void _skip() {
    Telemetry.log('demo_skip', {'level': _current.id});
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final level = _current;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(level),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                itemCount: _msgs.length,
                itemBuilder: (_, i) => _bubble(_msgs[i], level.tint),
              ),
            ),
            if (_coachUp) _coachCard(level),
            _composer(level),
          ],
        ),
      ),
    );
  }

  Widget _header(_Level level) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Glass.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: level.tint.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(level.avatar, style: const TextStyle(fontSize: 19)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text(level.tag,
                    style: const TextStyle(fontSize: 12, color: Glass.inkSoft)),
              ],
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < _levels.length; i++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= _level ? Glass.ink : Glass.hairline,
                  ),
                ),
            ],
          ),
          TextButton(
            onPressed: _skip,
            child: const Text('Skip',
                style: TextStyle(fontSize: 15, color: Glass.inkSoft)),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m, Color tint) {
    final radius = BorderRadius.circular(20);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            m.mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: m.mine ? const Color(0xFF0A84FF) : const Color(0xFFEFEFF4),
                    borderRadius: radius,
                  ),
                  child: Text(
                    m.text,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.28,
                      color: m.mine ? Colors.white : Glass.ink,
                    ),
                  ),
                ),
                if (m.tapback != null)
                  Positioned(
                    top: -14,
                    left: m.mine ? -8 : null,
                    right: m.mine ? null : -8,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 6,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      child: Text(m.tapback!,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coachCard(_Level level) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Glass.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Glass.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.coach,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(level.how,
                    style: const TextStyle(
                        fontSize: 13, height: 1.35, color: Glass.inkSoft)),
              ],
            ),
          ),
          if (level.demoText != null)
            TextButton(
              onPressed: _showMe,
              child: const Text('Show me',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Glass.accent)),
            ),
        ],
      ),
    );
  }

  Widget _composer(_Level level) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Glass.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: const Color(0x22000000)),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 9),
                    hintText: 'Message',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFF0A84FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward,
                    color: Colors.white, size: 19),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
