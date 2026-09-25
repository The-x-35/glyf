import 'package:flutter/widgets.dart';

/// A tap outside a text field puts the keyboard away, the way it does on the
/// tabs (AppShell). For pushed screens with fields of their own; the tour's
/// chats keep the keyboard up on purpose, so this isn't app-wide.
class DismissKeyboard extends StatelessWidget {
  const DismissKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      );
}
