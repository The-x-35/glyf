import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'chat_parts.dart';
import 'tour_scenarios.dart';

/// The tour's chats, a card at a time: who is asking, what they ask, and the
/// website's headline for it. The cards move on by themselves until someone
/// touches them; tapping one opens that chat.
class TourPreview extends StatefulWidget {
  const TourPreview({super.key, required this.onOpen});

  final ValueChanged<int> onOpen;

  @override
  State<TourPreview> createState() => _TourPreviewState();
}

class _TourPreviewState extends State<TourPreview> {
  static const _dwell = Duration(milliseconds: 3400);
  static const _turn = Duration(milliseconds: 650);
  static const _glide = Cubic(0.65, 0, 0.35, 1);
  static const _maxCard = 300.0;

  /// Below each card, inside the pages, so its shadow isn't cut off.
  static const _shadowRoom = 22.0;
  static const _grey = Color(0xFFE9E9EB);

  final _pages = PageController(viewportFraction: 0.86);
  Timer? _timer;
  int _page = 0;
  bool _held = false;

  int get _count => tourScenarios.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _queue());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// The next card in a moment, unless someone has taken over.
  void _queue() {
    _timer?.cancel();
    if (!mounted || _held || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return;
    _timer = Timer(_dwell, () {
      if (mounted && !_held && _pages.hasClients) _pages.nextPage(duration: _turn, curve: _glide);
    });
  }

  void _hold() {
    _held = true;
    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cardHeight = math.max(0.0, math.min(_maxCard, box.maxHeight - _shadowRoom - 10));
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
          height: cardHeight + _shadowRoom + 4,
          child: Listener(
            onPointerDown: (_) => _hold(),
            // Endless to the right, so it can keep turning: card 9 is card 1.
            child: PageView.builder(
              controller: _pages,
              onPageChanged: (i) {
                setState(() => _page = i);
                _queue();
              },
              itemBuilder: (context, i) => _settled(i, _card(i % _count)),
            ),
          ),
        ),
        _dots(),
      ]);
    });
  }

  /// Cards either side sit a touch smaller than the one in front.
  Widget _settled(int i, Widget card) => AnimatedBuilder(
        animation: _pages,
        child: card,
        builder: (context, child) {
          final page = _pages.hasClients && _pages.position.haveDimensions
              ? _pages.page ?? _page.toDouble()
              : _page.toDouble();
          final off = (page - i).abs().clamp(0.0, 1.0);
          return Transform.scale(scale: 1 - 0.05 * off, child: child);
        },
      );

  Widget _card(int i) {
    final sc = tourScenarios[i];
    final asks = sc.beats.first.them.where((l) => !isSolAddress(l)).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, _shadowRoom),
      child: Semantics(
        identifier: 'onb:tour:${sc.id}',
        button: true,
        label: '${sc.name}: ${sc.headline.$1} ${sc.headline.$2}',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpen(i),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Glass.card,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Glass.hairline),
              boxShadow: const [
                BoxShadow(color: Color(0x0D000000), blurRadius: 24, offset: Offset(0, 10)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  TourAvatar(sc, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(sc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Glass.ink)),
                  ),
                  const SizedBox(width: 8),
                  _chip(sc),
                ]),
                Expanded(child: _asks(asks)),
                const SizedBox(height: 14),
                Text(sc.headline.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: _headline(Glass.ink)),
                Text(sc.headline.$2,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _headline(const Color(0xFFA2A7B0))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  static TextStyle _headline(Color color) => TextStyle(
        fontSize: 21,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: color,
      );

  Widget _chip(TourScenario sc) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sc.tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(sc.tag,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color.lerp(sc.tint, Colors.black, 0.3),
            )),
      );

  /// What they asked, newest at the bottom. On a short card the older
  /// messages slip under the top edge, the way a chat scrolls.
  Widget _asks(List<String> asks) {
    return LayoutBuilder(builder: (context, box) {
      return Stack(children: [
        Positioned.fill(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.bottomLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var k = 0; k < asks.length; k++)
                      _bubble(asks[k], maxWidth: box.maxWidth * 0.86, last: k == asks.length - 1),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Softens a message cut by the top edge; over empty card otherwise.
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 14,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Glass.card, Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  Widget _bubble(String text, {required double maxWidth, required bool last}) {
    Widget bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
      decoration: BoxDecoration(color: _grey, borderRadius: BorderRadius.circular(18)),
      child: Text(text,
          style: const TextStyle(fontSize: 15, height: 20 / 15, letterSpacing: -0.2, color: Colors.black)),
    );
    if (last) bubble = CustomPaint(painter: BubbleTail(color: _grey, mine: false), child: bubble);
    return Padding(padding: const EdgeInsets.only(top: 4), child: bubble);
  }

  Widget _dots() {
    final on = _page % _count;
    return SizedBox(
      height: 6,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < _count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: i == on ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == on ? Glass.ink : const Color(0xFFD5D8DE),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    );
  }
}
