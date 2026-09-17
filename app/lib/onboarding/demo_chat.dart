import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import 'tour_scenarios.dart';

/// The website's chats (tryglyf.com), as a phone app, on the real keyboard.
///
/// Same people, same messages, same order as the website: a friend asks,
/// the keyboard rings the one thing to tap (and says what to do), anything
/// that needs typing is typed for you, you send, they react and move on.
/// iMessage look: typing dots, Delivered and Read, reactions, place, video
/// and payment cards, a banner when the next friend writes, and the
/// Messages list one tap back.
class DemoChat extends StatefulWidget {
  const DemoChat({super.key, required this.onDone});
  final VoidCallback onDone;

  /// Set while the tour is open: the keyboard's Pay chip lands here, in a
  /// practice wallet, instead of the real one.
  static void Function(String? to, String? amount)? onPracticePay;

  @override
  State<DemoChat> createState() => _DemoChatState();
}

class _Msg {
  _Msg(this.text, {required this.mine, required this.at, this.copyable = false})
      : id = '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
  static int _seq = 0;
  final String id;
  final String text;
  final bool mine;
  final String at;
  final bool copyable;
  String? tapback;
}

class _Thread {
  final msgs = <_Msg>[];
  int beat = 0;
  bool typing = false;
  bool waiting = true;
  bool done = false;
  String? status;
}

const _imBlue = Color(0xFF0A84FF);
const _imGrey = Color(0xFFE9E9EB);
const _imMeta = Color(0xFF8E8E93);
const _accent = Color(0xFF7C5CFF);

String _clock() {
  final now = TimeOfDay.now();
  final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
  final m = now.minute.toString().padLeft(2, '0');
  return '$h:$m ${now.period == DayPeriod.am ? 'AM' : 'PM'}';
}

class _DemoChatState extends State<DemoChat> with TickerProviderStateMixin {
  final _threads = {for (final s in tourScenarios) s.id: _Thread()};
  final _started = <String>{};
  final _pending = <String, _Msg>{};
  int _active = 0;
  bool _listOpen = false;
  int? _banner;
  Timer? _bannerTimer;
  String? _menuFor;
  bool _copied = false;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  late final AnimationController _dots =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  TourVault _vault = const TourVault();
  /// Maps can only answer "near me" once the app knows roughly where that is.
  bool _nearbyOn = true;
  String? _savedOther;
  bool _typingFor = false;
  Timer? _autoTimer;
  Timer? _keyboardWatch;
  int _downTicks = 0;
  bool _askForTap = false;

  TourScenario get _sc => tourScenarios[_active];
  _Thread get _th => _threads[_sc.id]!;
  TourBeat get _beat => _sc.beats[math.min(_th.beat, _sc.beats.length - 1)];

  @override
  void initState() {
    super.initState();
    Telemetry.log('demo_start', {});
    DemoChat.onPracticePay = _practicePay;
    _controller.addListener(_textChanged);
    _loadVault();
    _saveOtherLanguage();
    GlyfBridge.locationStatus().then((s) {
      if (mounted) setState(() => _nearbyOn = s['enabled'] == true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _open(0));
  }

  @override
  void dispose() {
    DemoChat.onPracticePay = null;
    _bannerTimer?.cancel();
    _keyboardWatch?.cancel();
    _autoTimer?.cancel();
    _setStep(null);
    _restoreOtherLanguage();
    _controller.removeListener(_textChanged);
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    _pulse.dispose();
    _dots.dispose();
    super.dispose();
  }

  // MARK: shared state with the keyboard

  Future<void> _loadVault() async {
    final raw = await GlyfBridge.vaultList();
    if (raw == null || !mounted) return;
    try {
      final fields = (jsonDecode(raw) as Map)['fields'] as List? ?? const [];
      String? of(String kind) => fields
          .whereType<Map>()
          .where((f) => f['kind'] == kind && (f['value'] as String? ?? '').isNotEmpty)
          .map((f) => f['value'] as String)
          .firstOrNull;
      setState(() => _vault = TourVault(address: of('address'), upi: of('upi')));
    } catch (_) {}
  }

  /// Tells the keyboard which chat and step it is coaching. Empty while the
  /// friend is typing, so nothing is ringed mid-reply.
  /// One write at a time: two overlapping read-modify-writes of the shared
  /// settings lose one of the changes (the step would undo the language).
  Future<void> _writes = Future.value();
  Future<void> _update(Map<String, dynamic> Function(Map<String, dynamic>) change) {
    final next = _writes.then((_) => GlyfBridge.updateSharedSettings(change));
    _writes = next.catchError((_) {});
    return next;
  }

  Future<void> _setStep(String? step) => _update((s) {
        s.remove('tourHint');
        if (step == null) {
          s.remove('tourStep');
          s.remove('tourHintAt');
          s.remove('tourCopiedAt');
        } else {
          s['tourStep'] = step;
          s['tourHintAt'] = DateTime.now().millisecondsSinceEpoch;
        }
        return s;
      });

  Future<void> _saveOtherLanguage() async {
    final s = await GlyfBridge.sharedSettings();
    _savedOther = s['translateOther'] as String?;
  }

  Future<void> _setOtherLanguage(String? language) =>
      _update((s) {
        if (language == null) {
          s.remove('translateOther');
        } else {
          s['translateOther'] = language;
        }
        return s;
      });

  void _restoreOtherLanguage() => _setOtherLanguage(_savedOther);

  // MARK: the chat engine (the website's, beat for beat)

  void _patch(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _open(int index) async {
    _bannerTimer?.cancel();
    _patch(() {
      _active = index;
      _banner = null;
      _listOpen = false;
      _menuFor = null;
      _copied = false;
    });
    _controller.clear();
    _seed();
    _toBottom();
    await _raiseKeyboard();
    final sc = tourScenarios[index];
    if (!_started.contains(sc.id)) {
      _started.add(sc.id);
      await _startBeat(index, 0);
    }
  }

  Future<void> _startBeat(int index, int beat) async {
    final sc = tourScenarios[index];
    final th = _threads[sc.id]!;
    _patch(() {
      th.beat = beat;
      th.waiting = true;
    });
    if (_active == index) _setStep(null);
    await Future.delayed(Duration(milliseconds: beat == 0 ? 500 : 300));
    await _theyType(index, sc.beats[beat].them);
    if (_active == index) {
      _patch(() => th.waiting = false);
      _seed();
    }
    _ready(index);
  }

  Future<void> _theyType(int index, List<String> lines) async {
    final th = _threads[tourScenarios[index].id]!;
    for (final line in lines) {
      _patch(() => th.typing = true);
      if (_active == index) _toBottom();
      await Future.delayed(Duration(milliseconds: math.min(1700, 700 + line.length * 20)));
      if (!mounted) return;
      _patch(() {
        th.typing = false;
        th.msgs.add(_Msg(line, mine: false, at: _clock(), copyable: isSolAddress(line)));
      });
      if (_active == index) _toBottom();
      await Future.delayed(const Duration(milliseconds: 420));
    }
  }

  /// The friend is listening again: answer anything sent while they typed.
  void _ready(int index) {
    final sc = tourScenarios[index];
    final th = _threads[sc.id]!;
    _patch(() => th.waiting = false);
    if (_active == index && !th.done) {
      _setStep('${sc.id}:${th.beat}');
      Future.delayed(const Duration(milliseconds: 400), _textChanged);
    }
    final queued = _pending.remove(sc.id);
    if (queued != null) _judge(index, queued);
  }

  /// A beat's starting text and language, once the friend has asked.
  void _seed() {
    final th = _th;
    final ready = !th.waiting && !th.done;
    final beat = _beat;
    if (ready && beat.prefill != null && _controller.text.isEmpty) {
      _typeIn(beat.prefill!, instant: true);
    }
    _setOtherLanguage(ready && beat.otherLanguage != null ? beat.otherLanguage : _savedOther);
    if (ready) {
      _setStep('${_sc.id}:${th.beat}');
      // Anything the friend's question starts typing for you.
      Future.delayed(const Duration(milliseconds: 400), _textChanged);
    }
  }

  void _onSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final index = _active;
    final sc = _sc;
    final th = _th;
    final msg = _Msg(text, mine: true, at: _clock());
    _patch(() {
      th.msgs.add(msg);
      th.status = 'Delivered';
      _menuFor = null;
    });
    _controller.clear();
    _toBottom();
    Telemetry.log('demo_send', {'chat': sc.id, 'beat': th.beat});
    if (th.done) return;
    if (th.waiting) {
      _pending[sc.id] = msg;
    } else {
      _judge(index, msg);
    }
  }

  Future<void> _judge(int index, _Msg msg) async {
    final sc = tourScenarios[index];
    final th = _threads[sc.id]!;
    if (th.done) return;
    final beat = sc.beats[th.beat];
    final ok = beat.goal(msg.text, _vault);
    _patch(() => th.waiting = true);
    if (_active == index) _setStep(null);
    await Future.delayed(const Duration(milliseconds: 850));
    _patch(() => th.status = 'Read');
    await Future.delayed(const Duration(milliseconds: 450));
    if (!ok) {
      await _theyType(index, [beat.nudge]);
      if (_active == index && beat.prefill != null) {
        _patch(() => th.waiting = false);
        _seed();
      }
      return _ready(index);
    }
    if (beat.tapback != null) {
      _patch(() => msg.tapback = beat.tapback);
      await Future.delayed(const Duration(milliseconds: 650));
    }
    await _theyType(index, beat.reply(msg.text));
    if (th.beat + 1 < sc.beats.length) {
      await _startBeat(index, th.beat + 1);
      return;
    }
    _patch(() {
      th.done = true;
      th.waiting = false;
    });
    Telemetry.log('demo_chat_done', {'chat': sc.id});
    await Future.delayed(const Duration(milliseconds: 700));
    if (_active != index || !mounted) return;
    final next = index + 1 < tourScenarios.length ? index + 1 : -1;
    _patch(() => _banner = next);
    // Banners slide away like iOS ones; the next friend opens on their own.
    _bannerTimer = Timer(const Duration(milliseconds: 3200), () {
      if (!mounted || _banner != next) return;
      next == -1 ? _finish() : _open(next);
    });
  }

  Future<void> _finish() async {
    Telemetry.log('demo_complete', {});
    await _setStep(null);
    _restoreOtherLanguage();
    widget.onDone();
  }

  // MARK: typing for you

  void _textChanged() {
    if (!mounted) return;
    setState(() {});
    if (_typingFor) return;
    // The keyboard changes text in several steps (a correction deletes the
    // word, then types the new one): only a settled box gets typed into.
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(milliseconds: 650), _autotype);
  }

  void _autotype() {
    if (!mounted || _typingFor) return;
    final auto = _beat.autotype;
    if (auto == null || _th.waiting || _th.done) return;
    final next = auto(_controller.text);
    if (next != null) _typeIn(next);
  }

  /// Types into the box the way a person does, a letter at a time, so the
  /// keyboard sees every change (and suggests, corrects, calculates).
  Future<void> _typeIn(String text, {bool instant = false}) async {
    if (instant) {
      final t = _controller.text + text;
      _controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
      return;
    }
    _typingFor = true;
    for (final ch in text.characters) {
      if (!mounted) break;
      final t = _controller.text + ch;
      _controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
      await Future.delayed(const Duration(milliseconds: 55));
    }
    _typingFor = false;
  }

  // MARK: the keyboard staying up

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

  /// Down for four seconds while a chat waits on you: ask for the tap.
  void _watchKeyboard() {
    _keyboardWatch?.cancel();
    _downTicks = 0;
    _keyboardWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final down = MediaQuery.viewInsetsOf(context).bottom == 0 && !_listOpen;
      _downTicks = down && !_th.waiting && !_th.done ? _downTicks + 1 : 0;
      final ask = _downTicks >= 8;
      if (ask != _askForTap) setState(() => _askForTap = ask);
    });
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  // MARK: Semi's payment, practised

  Future<void> _practicePay(String? to, String? amount) async {
    if (_sc.id != 'semi') return;
    final value = amount ?? _beat.payAmount ?? '200';
    final address = to ?? semiWallet;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _PracticeWallet(amount: value, to: address, name: _sc.name),
    );
    if (sent != true || !mounted) return;
    _controller.value = TextEditingValue(
      text: '💸 $value USDC · sent privately',
      selection: TextSelection.collapsed(offset: '💸 $value USDC · sent privately'.length),
    );
    _focus.requestFocus();
  }

  // MARK: build

  @override
  Widget build(BuildContext context) {
    final th = _th;
    final goalMet = !th.waiting && !th.done && _controller.text.trim().isNotEmpty &&
        _beat.goal(_controller.text.trim(), _vault);
    final bubbleCoach = _bubbleCoach();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _headlineBar(),
          Expanded(
            child: Stack(children: [
              Column(children: [
                _chatHeader(),
                Expanded(child: _thread(bubbleCoach)),
              ]),
              if (_banner != null) Positioned(top: 8, left: 12, right: 12, child: _bannerView(_banner!)),
              if (_listOpen) Positioned.fill(child: _messagesList()),
            ]),
          ),
          if (_askForTap && !_listOpen) _coachPill('Tap the message box'),
          if (_missing() != null && !_listOpen) _addDetail(_missing()!),
          _composer(goalMet),
        ]),
      ),
    );
  }

  /// A chat that needs a saved detail the vault does not have yet.
  (String kind, String label)? _missing() {
    final th = _th;
    if (th.waiting || th.done) return null;
    final step = '${_sc.id}:${th.beat}';
    if (step == 'sakshi:0' && !_nearbyOn) return ('nearby', 'nearby');
    if (step == 'mumma:0' && _vault.address == null) return ('address', 'address');
    if (step == 'zoya:1' && _vault.upi == null) return ('upi', 'UPI ID');
    return null;
  }

  Widget _addDetail((String, String) need) {
    final (kind, label) = need;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => kind == 'nearby' ? _turnOnNearby() : _saveDetail(kind, label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(980),
            boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(kind == 'nearby' ? Icons.near_me_rounded : Icons.lock_outline_rounded,
                size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(kind == 'nearby' ? 'Turn on nearby search' : 'Add your $label',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Future<void> _turnOnNearby() async {
    final res = await GlyfBridge.locationEnable();
    if (!mounted) return;
    setState(() => _nearbyOn = res['ok'] == true);
    Telemetry.log('tour_nearby', {'granted': _nearbyOn});
    _raiseKeyboard();
  }

  Future<void> _saveDetail(String kind, String label) async {
    final ctl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your $label', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            autofocus: true,
            minLines: 1,
            maxLines: kind == 'address' ? 3 : 1,
            keyboardType: kind == 'upi' ? TextInputType.emailAddress : TextInputType.streetAddress,
            decoration: InputDecoration(
              hintText: kind == 'upi' ? 'name@bank' : 'Flat, street, city, PIN',
              filled: true,
              fillColor: const Color(0xFFF2F3F7),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              label: 'Save to vault',
              onPressed: () async {
                final value = ctl.text.trim();
                if (value.isEmpty) return;
                final res = await GlyfBridge.vaultUpsertField(
                    kind: kind, label: kind == 'upi' ? 'UPI' : 'Home', value: value);
                if (ctx.mounted) Navigator.of(ctx).pop(res.ok);
              },
            ),
          ),
        ]),
      ),
    );
    if (saved == true) {
      Telemetry.log('vault_field_saved', {'kind': kind, 'from': 'tour'});
      await _loadVault();
    }
    _raiseKeyboard();
  }

  /// What the chat itself wants tapped (a bubble to copy), if anything.
  String? _bubbleCoach() {
    final th = _th;
    if (_sc.id != 'semi' || th.waiting || th.done || _copied) return null;
    if (_controller.text.isNotEmpty) return null;
    return _menuFor != null ? 'copy' : 'bubble';
  }

  Widget _headlineBar() {
    final (a, b) = _sc.headline;
    return SizedBox(
      height: 44,
      child: Row(children: [
        IconButton(
          onPressed: _finish,
          icon: const Icon(Icons.close_rounded, color: _imMeta, size: 22),
        ),
        Expanded(
          child: Text('$a $b',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ),
        TextButton(
          onPressed: () {
            Telemetry.log('demo_skip', {'chat': _sc.id});
            _active + 1 < tourScenarios.length ? _open(_active + 1) : _finish();
          },
          child: Text(_active + 1 < tourScenarios.length ? 'Skip' : 'Done',
              style: const TextStyle(fontSize: 15, color: _imMeta)),
        ),
      ]),
    );
  }

  Widget _avatar(TourScenario sc, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(Colors.white, sc.tint, 0.16)!,
              Color.lerp(Colors.white, sc.tint, 0.36)!,
            ],
          ),
          border: Border.all(color: sc.tint.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Text(sc.avatar, style: TextStyle(fontSize: size * 0.5)),
      );

  Widget _glass({required Widget child, EdgeInsets? padding, double radius = 22}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F9),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x14000000), width: 0.5),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: child,
      );

  Widget _chatHeader() {
    final unread = [
      for (var i = 0; i < tourScenarios.length; i++)
        if (i != _active && !_threads[tourScenarios[i].id]!.done) i,
    ].length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () {
                setState(() => _listOpen = true);
                _setStep(null);
              },
              child: _glass(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: Colors.black),
                  if (unread > 0) ...[
                    const SizedBox(width: 4),
                    Text('$unread', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),
            ),
          ),
        ),
        Column(children: [
          _avatar(_sc, 46),
          const SizedBox(height: 3),
          _glass(
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_sc.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 13, color: _imMeta),
            ]),
          ),
        ]),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _glass(
              padding: const EdgeInsets.all(10),
              child: const Icon(Icons.videocam_outlined, size: 22, color: Colors.black),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _thread(String? bubbleCoach) {
    final th = _th;
    final msgs = th.msgs;
    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Today ', style: TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: msgs.isNotEmpty ? msgs.first.at : '9:41 AM'),
          ]), style: const TextStyle(fontSize: 11, color: _imMeta)),
        ),
      ),
    ];
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final prev = i > 0 ? msgs[i - 1] : null;
      final next = i + 1 < msgs.length ? msgs[i + 1] : null;
      items.add(_bubble(
        m,
        first: prev == null || prev.mine != m.mine,
        last: next == null || next.mine != m.mine,
        coach: m.copyable ? bubbleCoach : null,
      ));
    }
    if (msgs.isNotEmpty && msgs.last.mine && th.status != null) {
      items.add(Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 3, right: 4),
          child: Text(th.status!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _imMeta)),
        ),
      ));
    }
    if (th.typing) items.add(_typingBubble());
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      children: items,
    );
  }

  Widget _typingBubble() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: _imGrey, borderRadius: BorderRadius.circular(19)),
            child: AnimatedBuilder(
              animation: _dots,
              builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  () {
                    final phase = ((_dots.value - i * 0.13) % 1.0);
                    final up = phase < 0.3 ? phase / 0.3 : phase < 0.6 ? 1 - (phase - 0.3) / 0.3 : 0.0;
                    return Transform.scale(
                      scale: 0.85 + 0.15 * up,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _imMeta.withValues(alpha: 0.35 + 0.65 * up),
                        ),
                      ),
                    );
                  }(),
                ],
              ]),
            ),
          ),
        ),
      );

  Widget _bubble(_Msg m, {required bool first, required bool last, String? coach}) {
    final width = MediaQuery.sizeOf(context).width;
    final rich = _rich(m);
    final isCoach = coach == 'bubble';
    final menuOpen = _menuFor == m.id;
    Widget body = rich ??
        Container(
          constraints: BoxConstraints(maxWidth: width * 0.76),
          padding: const EdgeInsets.fromLTRB(13, 7, 13, 8),
          decoration: BoxDecoration(
            color: m.mine ? _imBlue : _imGrey,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Text(m.text,
              style: TextStyle(fontSize: 16, height: 21 / 16, letterSpacing: -0.2,
                  color: m.mine ? Colors.white : Colors.black)),
        );
    if (last && rich == null) {
      body = CustomPaint(
        foregroundPainter: null,
        painter: _Tail(color: m.mine ? _imBlue : _imGrey, mine: m.mine),
        child: body,
      );
    }
    if (isCoach) {
      body = AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            boxShadow: [
              const BoxShadow(color: _accent, spreadRadius: 2.5),
              BoxShadow(
                color: _accent.withValues(alpha: 0.45 * (1 - _pulse.value)),
                spreadRadius: 2.5 + 12 * _pulse.value,
              ),
            ],
          ),
          child: child,
        ),
        child: body,
      );
    }
    body = GestureDetector(
      onTap: m.copyable ? () => setState(() => _menuFor = menuOpen ? null : m.id) : null,
      child: body,
    );
    return Padding(
      padding: EdgeInsets.only(top: m.tapback != null ? 24 : first ? 10 : 2),
      child: Column(
        crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (menuOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
              child: _copyMenu(coach == 'copy', m),
            ),
          Stack(clipBehavior: Clip.none, children: [
            body,
            if (isCoach) Positioned(top: -38, left: 0, child: _label('Tap to copy')),
            if (m.tapback != null)
              Positioned(
                top: -21,
                left: m.mine ? -15 : null,
                right: m.mine ? null : -15,
                child: Container(
                  width: 34,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _imGrey,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                  child: Text(m.tapback!, style: const TextStyle(fontSize: 15)),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _copyMenu(bool coach, _Msg m) {
    Widget item = GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: m.text));
        // The keyboard cannot read the clipboard to know this was the
        // address, so the tour tells it.
        await _update((s) => s..['tourCopiedAt'] = DateTime.now().millisecondsSinceEpoch);
        setState(() {
          _menuFor = null;
          _copied = true;
        });
        _raiseKeyboard();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: coach ? const [BoxShadow(color: _accent, spreadRadius: 2.5)] : null,
          color: Colors.white,
        ),
        child: const Text('Copy', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    );
    return Stack(clipBehavior: Clip.none, children: [
      _glass(radius: 14, padding: const EdgeInsets.all(4), child: item),
      if (coach) Positioned(top: -38, left: 0, child: _label('Copy')),
    ]);
  }

  /// The website's coach: a purple pill with a point, over the thing to tap.
  Widget _label(String text) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(980),
            boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        CustomPaint(size: const Size(12, 6), painter: _Point()),
      ]);

  Widget _coachPill(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _label(text),
      );

  /// Places, videos and payments arrive as cards, the way both apps show them.
  Widget? _rich(_Msg m) {
    final t = m.text;
    if (t.startsWith('💸 ')) {
      final amount = t.substring(3).split(' · ').first.replaceAll(RegExp(r' (USDC|SOL)$'), '');
      return Container(
        width: 230,
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1D1D1F), Color(0xFF2D2150), Color(0xFF4B2A86)],
            stops: [0, 0.6, 1],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lock_rounded, size: 12, color: Color(0xBFFFFFFF)),
            SizedBox(width: 5),
            Text('Sent privately',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xBFFFFFFF))),
          ]),
          const SizedBox(height: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(amount,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -1.2, color: Colors.white)),
            const SizedBox(width: 8),
            const Text('USDC', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF))),
          ]),
          const SizedBox(height: 2),
          const Text('Solana · MagicBlock', style: TextStyle(fontSize: 11.5, color: Color(0xA6FFFFFF))),
        ]),
      );
    }
    final place = t.contains('📍');
    final video = t.contains('youtu') || t.contains('🎥');
    if (!place && !video) return null;
    final title = place
        ? placeName(t)
        : t.split('\n').firstWhere((l) => l.contains('🎥'), orElse: () => t).replaceFirst(RegExp(r'^.*🎥\s*'), '');
    final seed = title.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff);
    final videoId = RegExp(r'(?:youtu\.be/|[?&]v=)([\w-]{11})').firstMatch(t)?.group(1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: Container(
        width: 250,
        color: _imGrey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 120,
            width: 250,
            child: place
                ? CustomPaint(painter: _MiniMapPainter(seed))
                : DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          HSLColor.fromAHSL(1, (seed % 360).toDouble(), 0.7, 0.6).toColor(),
                          HSLColor.fromAHSL(1, ((seed % 360) + 40) % 360 * 1.0, 0.6, 0.34).toColor(),
                        ],
                      ),
                      // The video's own thumbnail, as Messages shows a link.
                      image: videoId == null
                          ? null
                          : DecorationImage(
                              image: NetworkImage('https://i.ytimg.com/vi/$videoId/hqdefault.jpg'),
                              fit: BoxFit.cover,
                              onError: (_, _) {},
                            ),
                    ),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x73000000)),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
              Text(place ? 'Maps' : 'youtube.com', style: const TextStyle(fontSize: 13, color: _imMeta)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bannerView(int next) {
    final last = next == -1;
    final sc = last ? null : tourScenarios[next];
    return GestureDetector(
      onTap: () {
        _bannerTimer?.cancel();
        last ? _finish() : _open(next);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
        decoration: BoxDecoration(
          color: const Color(0xF2FAFAFC),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 40, offset: Offset(0, 16), spreadRadius: -16)],
          border: Border.all(color: const Color(0x1F000000), width: 0.5),
        ),
        child: Row(children: [
          if (sc != null)
            _avatar(sc, 38)
          else
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1D1D1F)),
              child: const Text('g', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 19)),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sc?.name ?? 'Glyf', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(sc?.teaser ?? "That's everyone. You're ready.",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF3C3C43))),
            ]),
          ),
          if (sc != null) const Text('now', style: TextStyle(fontSize: 12, color: _imMeta)),
        ]),
      ),
    );
  }

  Widget _messagesList() {
    return Container(
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text('Messages', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1)),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() => _listOpen = false);
              _seed();
            },
            child: const Text('Back', style: TextStyle(fontSize: 16, color: _imBlue)),
          ),
        ]),
        Expanded(
          child: ListView.builder(
            itemCount: tourScenarios.length,
            itemBuilder: (_, i) {
              final sc = tourScenarios[i];
              final th = _threads[sc.id]!;
              final last = th.msgs.isNotEmpty ? th.msgs.last : null;
              final pending = !th.done && i != _active;
              return InkWell(
                onTap: () => _open(i),
                child: SizedBox(
                  height: 78,
                  child: Row(children: [
                    SizedBox(
                      width: 22,
                      child: Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: pending ? _imBlue : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                    _avatar(sc, 52),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 78,
                        padding: const EdgeInsets.only(right: 16),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0x1F000000), width: 0.5)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(sc.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              if (th.done) const Icon(Icons.check_circle, size: 16, color: Color(0xFF34C759)),
                              if (th.done) const SizedBox(width: 6),
                              Text(last?.at ?? earlierTimes[i], style: const TextStyle(fontSize: 13, color: _imMeta)),
                              const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFC7C7CC)),
                            ]),
                            Text(last?.text.replaceAll('\n', ' ') ?? sc.teaser,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, height: 20 / 15, color: _imMeta)),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _composer(bool goalMet) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
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
                  hintText: 'iMessage',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            GestureDetector(
              onTap: _onSend,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: goalMet
                        ? [
                            const BoxShadow(color: _accent, spreadRadius: 2.5),
                            BoxShadow(
                              color: _accent.withValues(alpha: 0.45 * (1 - _pulse.value)),
                              spreadRadius: 2.5 + 12 * _pulse.value,
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                ),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: _imBlue, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                ),
              ),
            ),
            if (goalMet) Positioned(top: -44, right: -4, child: _label('Send')),
          ]),
        ]),
      ),
    );
  }
}

/// The iMessage tail on the last bubble of a run.
class _Tail extends CustomPainter {
  _Tail({required this.color, required this.mine});
  final Color color;
  final bool mine;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final h = size.height;
    final w = size.width;
    final path = Path();
    if (mine) {
      path
        ..moveTo(w - 14, h - 14)
        ..quadraticBezierTo(w - 4, h - 2, w + 6, h)
        ..quadraticBezierTo(w - 6, h + 1, w - 18, h - 4)
        ..close();
    } else {
      path
        ..moveTo(14, h - 14)
        ..quadraticBezierTo(4, h - 2, -6, h)
        ..quadraticBezierTo(6, h + 1, 18, h - 4)
        ..close();
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_Tail old) => old.color != color || old.mine != mine;
}

class _Point extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = _accent,
    );
  }

  @override
  bool shouldRepaint(_Point old) => false;
}

/// A little map for a shared place: streets, a park, a pin.
class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter(this.seed);
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEFEAE0));
    final park = Paint()..color = const Color(0xFFCDE8C3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.nextDouble() * size.width * 0.6, r.nextDouble() * size.height * 0.5, 70, 44),
        const Radius.circular(8),
      ),
      park,
    );
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.2 + 0.3 * i) + r.nextDouble() * 10;
      canvas.drawLine(Offset(-10, y), Offset(size.width + 10, y + r.nextDouble() * 20 - 10), road);
    }
    for (var i = 0; i < 3; i++) {
      final x = size.width * (0.15 + 0.33 * i) + r.nextDouble() * 12;
      canvas.drawLine(Offset(x, -10), Offset(x + r.nextDouble() * 24 - 12, size.height + 10), road);
    }
    final pin = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(pin, 11, Paint()..color = const Color(0xFFFF3B30));
    canvas.drawCircle(pin, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) => old.seed != seed;
}

/// Semi's payment, practised: the wallet sheet, nothing actually sent.
class _PracticeWallet extends StatelessWidget {
  const _PracticeWallet({required this.amount, required this.to, required this.name});
  final String amount;
  final String to;
  final String name;

  @override
  Widget build(BuildContext context) {
    final short = to.length > 12 ? '${to.substring(0, 4)}…${to.substring(to.length - 4)}' : to;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Pay $name', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(amount, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -2)),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('USDC', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('to $short on Solana', style: const TextStyle(fontSize: 14, color: Glass.inkSoft)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(children: [
              Icon(Icons.lock_rounded, size: 18, color: _accent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Private payment by MagicBlock',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          PillButton(label: 'Send privately', onPressed: () => Navigator.of(context).pop(true)),
        ]),
      ),
    );
  }
}
