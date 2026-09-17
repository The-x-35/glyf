import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// The website's guided chat, played on the real keyboard.
///
/// tryglyf.com walks a visitor through Glyf by handing them a thread and a
/// job. Here the message is already typed for them and the keyboard itself
/// rings the one thing to tap (the answer in the strip, the space bar, the
/// emoji key), so every level is a tap or a hold, never typing. Then send.
class DemoChat extends StatefulWidget {
  const DemoChat({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<DemoChat> createState() => _DemoChatState();
}

/// One person, one thing they want, one tap that gets it done.
class _Level {
  const _Level({
    required this.id,
    required this.name,
    required this.avatar,
    required this.tint,
    required this.tag,
    required this.them,
    required this.prefill,
    required this.hint,
    required this.coach,
    required this.goal,
    required this.reply,
    required this.tapback,
  });

  final String id;
  final String name;
  final String avatar;
  final Color tint;
  final String tag;
  final List<String> them;
  /// Typed into the message for them, so the level is a tap, not typing.
  final String prefill;
  /// What the keyboard rings: "chip", "space", "emojikey", or a letter.
  final String hint;
  final String coach;
  final bool Function(String text, _VaultPeek vault) goal;
  final List<String> reply;
  final String tapback;
}

/// What the vault holds, so a level can check the real answer went in.
class _VaultPeek {
  const _VaultPeek(this.values);
  final List<String> values;
  bool matched(String text) {
    final t = text.toLowerCase();
    return values.any((v) => v.length > 3 && t.contains(v.toLowerCase()));
  }
}

const _roughReply = 'ya ok will send deck b4 6';

final _levels = <_Level>[
  _Level(
    id: 'math',
    name: 'Zoya',
    avatar: '🍕',
    tint: const Color(0xFFFF9F0A),
    tag: 'Maths, mid-sentence',
    them: ['dinner was 3480 for the four of us 😭', 'how much do i owe you?'],
    prefill: '3480/4',
    hint: 'chip',
    coach: 'Tap the answer in the strip',
    goal: (text, _) => text.contains('870'),
    reply: ['perfect, sending now 🙏', 'you\'re the best'],
    tapback: '🙏',
  ),
  _Level(
    id: 'vault',
    name: 'Mumma',
    avatar: '🎁',
    tint: const Color(0xFFFF6FAE),
    tag: 'Never type it again',
    them: ['hi beta 🎉', 'sending you something', 'what\'s your address?'],
    prefill: 'my address is ',
    hint: 'chip',
    coach: 'Tap your address in the strip',
    goal: (text, vault) => vault.values.isEmpty
        ? text.trim().length > 'my address is '.length + 4
        : vault.matched(text),
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
    prefill: _roughReply,
    hint: 'space',
    coach: 'Hold the space bar, then pick one',
    goal: (text, _) =>
        text.trim().toLowerCase() != _roughReply && text.trim().length > 18,
    reply: ['amazing, thank you!', 'see you at the review 🙌'],
    tapback: '👍',
  ),
  _Level(
    id: 'emoji',
    name: 'Rohan',
    avatar: '🏏',
    tint: const Color(0xFF32D583),
    tag: 'The rest of it',
    them: ['we won 🏆', 'still can\'t believe that last over'],
    prefill: 'what a finish ',
    hint: 'emojikey',
    coach: 'Tap the emoji key and pick one',
    goal: (text, _) => text.runes.any((r) => r > 0x203F),
    reply: ['hahaha same 😭', 'next match you\'re coming'],
    tapback: '😂',
  ),
];

class _Msg {
  _Msg(this.text, {required this.mine});
  final String text;
  final bool mine;
  /// Set when the other side reacts to what you sent.
  String? tapback;
}

class _DemoChatState extends State<DemoChat> with SingleTickerProviderStateMixin {
  int _level = 0;
  final _msgs = <_Msg>[];
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);
  bool _busy = false;
  bool _coachUp = false;
  /// The keyboard has been down for a while during a level. Android can
  /// refuse (or later drop) a keyboard nobody tapped for; then the coach asks
  /// for the tap instead of pointing at keys nobody can see.
  bool _askedForKeyboard = false;
  Timer? _keyboardWatch;
  int _downTicks = 0;
  bool _ready = false;
  _VaultPeek _vault = const _VaultPeek([]);

  @override
  void initState() {
    super.initState();
    Telemetry.log('demo_start', {});
    _controller.addListener(_textChanged);
    _loadVault();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLevel());
  }

  @override
  void dispose() {
    _setHint(null);
    _keyboardWatch?.cancel();
    _controller.removeListener(_textChanged);
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    _pulse.dispose();
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
      // A vault we cannot read just means that level accepts any answer.
    }
  }

  _Level get _current => _levels[_level];

  /// Tells the keyboard what to ring. Written to shared settings, which the
  /// keyboard re-reads when the text changes.
  Future<void> _setHint(String? hint) => GlyfBridge.updateSharedSettings((s) {
        if (hint == null) {
          s.remove('tourHint');
          s.remove('tourHintAt');
        } else {
          s['tourHint'] = hint;
          s['tourHintAt'] = DateTime.now().millisecondsSinceEpoch;
        }
        return s;
      });

  Future<void> _runLevel() async {
    setState(() {
      _msgs.clear();
      _coachUp = false;
      _ready = false;
      _busy = true;
    });
    // The keyboard goes down while the next person's messages come in, and
    // comes back up with the reply already in the box. Pointing a keyboard
    // that is still up at a changed field races on Android and can leave it
    // attached to nothing.
    await _lowerKeyboard();
    if (!mounted) return;
    _controller.clear();
    for (final line in _current.them) {
      await Future.delayed(const Duration(milliseconds: 620));
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(line, mine: false)));
      _toBottom();
    }
    await Future.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    // The hint goes first: typing the message is what makes the keyboard
    // look again, and it should find the hint already there.
    await _setHint(_current.hint);
    setState(() {
      _busy = false;
      _coachUp = true;
    });
    await _prefill();
  }

  /// Puts the level's message in the box with the keyboard up and reading it.
  Future<void> _prefill() async {
    _controller.value = TextEditingValue(
      text: _current.prefill,
      selection: TextSelection.collapsed(offset: _current.prefill.length),
    );
    if (!_focus.hasFocus) _focus.requestFocus();
    await _raiseKeyboard();
  }

  Future<void> _lowerKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    for (var i = 0; i < 25; i++) {
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted || MediaQuery.viewInsetsOf(context).bottom == 0) return;
    }
  }

  /// The box brings the keyboard up itself when it takes focus. Only when
  /// nothing has come up after a generous wait (a slow phone animates the
  /// keyboard in for a couple of seconds), take focus again once.
  /// (Raw show and hide calls on top of that raced on Android: the keyboard
  /// attached, then dropped the box a moment later.)
  Future<void> _raiseKeyboard() async {
    _watchKeyboard();
    if (!_focus.hasFocus) _focus.requestFocus();
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted || MediaQuery.viewInsetsOf(context).bottom > 0) return;
    }
    _focus.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) _focus.requestFocus();
  }

  /// Down for 4 seconds in a row while a level waits for a tap: ask for it.
  void _watchKeyboard() {
    _keyboardWatch?.cancel();
    _downTicks = 0;
    _askedForKeyboard = false;
    _keyboardWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final down = MediaQuery.viewInsetsOf(context).bottom == 0;
      _downTicks = down && _coachUp && !_busy ? _downTicks + 1 : 0;
      final ask = _downTicks >= 8;
      if (ask != _askedForKeyboard) setState(() => _askedForKeyboard = ask);
    });
  }

  void _textChanged() {
    if (_busy || !_coachUp) return;
    final ready = _current.goal(_controller.text, _vault);
    if (ready == _ready) return;
    setState(() => _ready = ready);
    // Done on the keyboard: the ring moves to the send button.
    _setHint(ready ? null : _current.hint);
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
    final done = _current.goal(text, _vault);
    _controller.clear();
    setState(() {
      _msgs.add(_Msg(text, mine: true));
      _coachUp = false;
      _ready = false;
      _busy = true;
    });
    _toBottom();
    Telemetry.log('demo_send', {'level': _current.id, 'done': done});
    await Future.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;
    if (!done) {
      setState(() {
        _msgs.add(_Msg('hmm, try again? 🙈', mine: false));
        _busy = false;
        _coachUp = true;
      });
      _toBottom();
      await _prefill();
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
    _next();
  }

  /// On to the next person, or out when this was the last.
  Future<void> _next() async {
    if (_level >= _levels.length - 1) {
      Telemetry.log('demo_complete', {});
      await _setHint(null);
      widget.onDone();
      return;
    }
    setState(() {
      _level++;
      _busy = false;
    });
    _runLevel();
  }

  /// Skips this one demo, not the tour.
  void _skip() {
    if (_busy) return;
    Telemetry.log('demo_skip', {'level': _current.id});
    _next();
  }

  Future<void> _close() async {
    Telemetry.log('demo_close', {'level': _current.id});
    await _setHint(null);
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
                itemBuilder: (_, i) => _bubble(_msgs[i]),
              ),
            ),
            if (_coachUp) _coachCard(level),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header(_Level level) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 10, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Glass.hairline)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded, color: Glass.inkSoft),
          ),
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
          TextButton(
            onPressed: _skip,
            child: Text(_level >= _levels.length - 1 ? 'Done' : 'Skip',
                style: const TextStyle(fontSize: 15, color: Glass.inkSoft)),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
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

  /// One line: what to tap now. It changes to "Send it" once that is done.
  Widget _coachCard(_Level level) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: Glass.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Glass.accent.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(_ready ? Icons.arrow_upward_rounded : Icons.touch_app_rounded,
            size: 18, color: Glass.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              _ready
                  ? 'Now send it'
                  : _askedForKeyboard
                      ? 'Tap the message box'
                      : level.coach,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _composer() {
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
                  // The keyboard is what this screen teaches: tapping Send or
                  // the chat keeps it up and attached.
                  onTapOutside: (_) {},
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
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        width: 2.5,
                        color: _ready
                            ? Glass.accent.withValues(alpha: 0.25 + 0.75 * (1 - _pulse.value))
                            : Colors.transparent),
                  ),
                  child: child,
                ),
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
            ),
          ],
        ),
      ),
    );
  }
}
