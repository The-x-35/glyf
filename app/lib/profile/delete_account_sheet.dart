import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/theme.dart';

/// Delete account's confirmation (App Store 5.1.1(v), Google Play): what
/// goes, in two plain lines, then Delete account or Cancel. True once the
/// account is deleted and the phone erased; Cancel, a swipe down or a tap
/// outside leave everything as it was.
Future<bool> showDeleteAccountSheet(BuildContext context) async {
  final deleted = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    // A drag closes a sheet without asking it; Cancel, Back and a tap
    // outside ask, so one that is mid-delete can stay up until it is done.
    enableDrag: false,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (_) => const _DeleteAccountSheet(),
  );
  return deleted == true;
}

class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet();

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await Auth.deleteAccount();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = Theme.of(context).platform == TargetPlatform.iOS
        ? 'cancel it in Settings, under your Apple Account'
        : 'cancel it in Google Play';
    return PopScope(
      // Half deleted is not a state to leave in: it finishes, then closes.
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Delete your account?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text(
                  'Your Glyf account and what our server keeps for it are deleted, and the vault, notes, '
                  'clipboard, learned words and settings on this phone are erased. This can\'t be undone.',
                  key: Key('delete-account:what'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Glass.inkSoft, fontSize: 14, height: 1.4)),
              const SizedBox(height: 8),
              Text("A subscription isn't cancelled with it: $store.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Glass.inkSoft, fontSize: 14, height: 1.4)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    key: const Key('delete-account:error'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Glass.danger, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              Semantics(
                identifier: 'delete-account:confirm',
                button: true,
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Glass.danger,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Glass.danger.withValues(alpha: 0.55),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _busy ? null : _delete,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : const Text('Delete account'),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                identifier: 'delete-account:cancel',
                button: true,
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel',
                      style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
