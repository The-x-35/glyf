import 'dart:async';

import 'package:flutter/material.dart';

import '../build/build_tab.dart';
import '../core/ai_consent.dart';
import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../home/home_tab.dart';
import '../onboarding/demo_chat.dart';
import '../profile/profile_tab.dart';
import 'app_tour.dart';

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

  /// The app tour: Home's pieces and the tab buttons it rings, whether it is
  /// running, and whether the floating button has done its job (taken or
  /// put away: `appTourDone` in onboarding.json).
  final _homeKeys = HomeTourKeys();
  final _tabKeys = [GlobalKey(), GlobalKey(), GlobalKey()];
  bool _touring = false;
  bool _tourDone = true;

  @override
  void initState() {
    super.initState();
    AppShell.requestedTab.addListener(_onRequestedTab);
    appTourRequests.addListener(_startTour);
    _onRequestedTab();
    GlyfBridge.onboardingState().then((s) {
      if (mounted) setState(() => _tourDone = s['appTourDone'] == true);
    });
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
    appTourRequests.removeListener(_startTour);
    _activeTab.dispose();
    super.dispose();
  }

  /// The tour starts on Home, from the floating button or Profile › Tour.
  void _startTour() {
    if (_touring || !mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = 0;
      _touring = true;
    });
    _activeTab.value = 0;
    Telemetry.log('app_tour_start', {});
  }

  /// The tour's stops: Home's keyboard, a bound key (when there is one),
  /// the try field, Build, Profile, then the chats.
  List<AppTourStep> get _tourSteps => [
        AppTourStep(
          target: _homeKeys.keyboard,
          title: 'Your keyboard',
          body: 'Keys with a purple dot do something. Hold one in any app and Glyf does it.',
        ),
        if (_homeKeys.firstKey.currentContext != null)
          AppTourStep(
            target: _homeKeys.firstKey,
            title: 'Pick what a key does',
            body: 'Tap a key here, or on the keyboard above, to change what holding it does.',
          ),
        AppTourStep(
          target: _homeKeys.tryField,
          title: 'Try it here',
          body: 'Type with Glyf right in the app, no other app needed.',
        ),
        AppTourStep(
          target: _tabKeys[1],
          title: 'Build',
          body: 'Make your own glyfs, or add packs of them.',
        ),
        AppTourStep(
          target: _tabKeys[2],
          title: 'Profile',
          body: 'Your vault, keyboard settings and connected tools.',
        ),
        const AppTourStep(
          target: null,
          title: 'Now try it in real chats',
          body: 'Eight short chats on your own keyboard. A friend asks, and Glyf does it in a tap or two.',
        ),
      ];

  /// The tour is over: the floating button has done its job, and "Start the
  /// chats" goes straight into them.
  Future<void> _endTour(bool chats) async {
    setState(() {
      _touring = false;
      _tourDone = true;
    });
    Telemetry.log('app_tour_end', {'chats': chats});
    unawaited(_saveTourDone());
    if (!chats || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => DemoChat(onDone: () => Navigator.of(ctx).pop()),
    ));
  }

  /// The ✕ on the floating button: put away, the tour stays in Profile.
  void _dismissTourButton() {
    setState(() => _tourDone = true);
    Telemetry.log('app_tour_dismissed', {});
    unawaited(_saveTourDone());
  }

  Future<void> _saveTourDone() async {
    final s = await GlyfBridge.onboardingState();
    await GlyfBridge.saveOnboardingState({...s, 'appTourDone': true});
  }

  @override
  Widget build(BuildContext context) {
    final showTourButton = _index == 0 && !_tourDone && !_touring;
    final tabs = [
      HomeTab(activeTab: _activeTab, tourKeys: _homeKeys, roomBelow: showTourButton ? 64 : 0),
      BuildTab(activeTab: _activeTab),
      ProfileTab(onRerunOnboarding: widget.onRerunOnboarding, activeTab: _activeTab),
    ];
    final scaffold = Scaffold(
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
          // Home's floating "Take a tour" (the app, then the chats).
          Positioned(
            right: 16,
            bottom: 16,
            child: IgnorePointer(
              ignoring: !showTourButton,
              child: AnimatedSlide(
                offset: showTourButton ? Offset.zero : const Offset(0, 0.4),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: showTourButton ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: TakeTourButton(onTap: _startTour, onDismiss: _dismissTourButton),
                ),
              ),
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
    // The tour dims everything, the tab bar included, but what it rings.
    return Stack(children: [
      scaffold,
      if (_touring) Positioned.fill(child: AppTourOverlay(steps: _tourSteps, onEnd: _endTour)),
    ]);
  }

  Widget _tab(int i, String id, Widget icon) {
    final selected = _index == i;
    return Expanded(
      key: _tabKeys[i],
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
