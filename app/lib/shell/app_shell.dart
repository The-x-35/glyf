import 'package:flutter/material.dart';

import '../build/build_tab.dart';
import '../core/ai_consent.dart';
import '../core/theme.dart';
import '../home/home_tab.dart';
import '../profile/profile_tab.dart';

/// Three tabs — Home (the brand keycap), Build, Profile. The Builder lives
/// inside Build, so there's no separate ＋. Tabs crossfade and keep state.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.onRerunOnboarding});
  final VoidCallback onRerunOnboarding;

  /// A deep link asking for a tab (glyf://open?path=build).
  static final requestedTab = ValueNotifier<int?>(null);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _activeTab = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    AppShell.requestedTab.addListener(_onRequestedTab);
    _onRequestedTab();
    // Set up before "What Glyf sends" was asked: ask once, now.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await AiConsent.needed() && mounted) await showAiConsentSheet(context);
    });
  }

  void _onRequestedTab() {
    final i = AppShell.requestedTab.value;
    if (i == null) return;
    AppShell.requestedTab.value = null;
    setState(() => _index = i);
    _activeTab.value = i;
  }

  @override
  void dispose() {
    AppShell.requestedTab.removeListener(_onRequestedTab);
    _activeTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeTab(activeTab: _activeTab),
      BuildTab(activeTab: _activeTab),
      ProfileTab(onRerunOnboarding: widget.onRerunOnboarding, activeTab: _activeTab),
    ];
    return Scaffold(
      // Tapping anywhere outside a text field dismisses the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(children: [
          for (final (i, tab) in tabs.indexed)
            IgnorePointer(
              ignoring: _index != i,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                opacity: _index == i ? 1 : 0,
                child: tab,
              ),
            ),
        ]),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Glass.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                _tab(0, 'home', _GTabIcon(selected: _index == 0)),
                _tab(
                    1,
                    'build',
                    Icon(
                        _index == 1
                            ? Icons.grid_view_rounded
                            : Icons.grid_view_outlined,
                        size: 24,
                        color: _index == 1
                            ? Glass.ink
                            : const Color(0xFFA6ABB4))),
                _tab(
                    2,
                    'profile',
                    Icon(
                        _index == 2
                            ? Icons.person_rounded
                            : Icons.person_outline_rounded,
                        size: 25,
                        color: _index == 2
                            ? Glass.ink
                            : const Color(0xFFA6ABB4))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int i, String id, Widget icon) {
    final selected = _index == i;
    return Expanded(
      child: Semantics(
        identifier: 'tab:$id',
        button: true,
        label: id,
        child: InkWell(
          onTap: () {
            setState(() => _index = i);
            _activeTab.value = i;
          },
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            icon,
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 4 : 0,
              height: 4,
              decoration: const BoxDecoration(
                  color: Glass.accent, shape: BoxShape.circle),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The Home tab icon is the brand itself — a mini keycap-g.
class _GTabIcon extends StatelessWidget {
  const _GTabIcon({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Glass.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: selected
            ? null
            : Border.all(color: const Color(0xFFA6ABB4), width: 1.6),
      ),
      child: Text('g',
          style: TextStyle(
              color: selected ? Colors.white : const Color(0xFFA6ABB4),
              fontSize: 15,
              height: 1,
              fontWeight: FontWeight.w800)),
    );
  }
}
