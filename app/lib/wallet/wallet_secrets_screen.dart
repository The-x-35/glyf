import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/theme.dart';
import 'glyf_keys.dart';

/// The phone's own unlock before a secret is shown: Face ID, Touch ID or
/// the passcode (deviceAuth in the Runner bridge).
Future<bool> unlockWalletSecret(String reason) => GlyfBridge.deviceAuth(reason);

/// Copies [text] the way a wallet secret is copied (GlyfBridge.copySecret:
/// this phone only, gone in 60 s, never in clipboard history). No toast:
/// the button's own tick is the answer.
class SecretCopyButton extends StatefulWidget {
  const SecretCopyButton({super.key, required this.text, this.label = 'Copy', this.id});
  final String text;
  final String label;
  final String? id;

  @override
  State<SecretCopyButton> createState() => _SecretCopyButtonState();
}

class _SecretCopyButtonState extends State<SecretCopyButton> {
  bool _done = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    if (!await GlyfBridge.copySecret(widget.text)) return;
    if (!mounted) return;
    setState(() => _done = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () => mounted ? setState(() => _done = false) : null);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        identifier: widget.id,
        button: true,
        child: TextButton.icon(
          onPressed: _copy,
          icon: Icon(_done ? Icons.check_rounded : Icons.copy_rounded, size: 18, color: Glass.ink),
          label: Text(widget.label, style: const TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      );
}

/// Profile › Wallet › Recovery phrase: the 12 words, numbered.
class RecoveryPhraseScreen extends StatelessWidget {
  const RecoveryPhraseScreen({super.key, required this.phrase});
  final String phrase;

  @override
  Widget build(BuildContext context) {
    final words = phrase.split(' ');
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Recovery phrase', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Semantics(
              identifier: 'wallet:phrase',
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.6,
                children: [
                  for (var i = 0; i < words.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(color: Glass.bg, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            child: Text('${i + 1}',
                                style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ),
                          // The longest words (8 letters) shrink to fit, never clip.
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(words[i],
                                  maxLines: 1,
                                  style: const TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: SecretCopyButton(text: phrase, id: 'wallet:phrase:copy')),
        ],
      ),
    );
  }
}

/// Profile › Wallet › Private keys: Ethereum (0x hex) and Solana (base58,
/// the 64-byte secret Phantom imports), and the pre-phrase Ethereum key
/// while this phone still holds one.
class PrivateKeysScreen extends StatelessWidget {
  const PrivateKeysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?, String?, String)>[
      ('Ethereum', GlyfKeys.evmAddress.value, GlyfKeys.evmKeyHex, 'evm'),
      ('Solana', GlyfKeys.solanaAddress.value, GlyfKeys.solanaSecret, 'solana'),
      ('Ethereum (old)', GlyfKeys.oldEvmAddress.value, GlyfKeys.oldEvmKeyHex, 'evm-old'),
    ].where((r) => r.$3 != null).toList();
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Private keys', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 18, color: Glass.hairline),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rows[i].$1,
                                  style: const TextStyle(color: Glass.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                              if (rows[i].$2 != null)
                                Text(_short(rows[i].$2!),
                                    style: const TextStyle(
                                        color: Glass.inkSoft, fontSize: 13.5, fontFeatures: [FontFeature.disable('calt')])),
                            ],
                          ),
                        ),
                        SecretCopyButton(text: rows[i].$3!, id: 'wallet:key:${rows[i].$4}'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _short(String a) => a.length < 12 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';
}
