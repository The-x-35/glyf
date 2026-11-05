import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/theme.dart';
import 'arkiv_vault.dart';
import 'evm_rpc.dart';

/// Vault → Backup: the details, shorthand and combos, encrypted on this
/// phone and kept on Arkiv under a key only this person's iCloud Keychain
/// holds. Back up writes what changed; Restore puts it all back on a new
/// phone. Pictures stay on the phone.
class ArkivBackupCard extends StatefulWidget {
  const ArkivBackupCard({super.key, required this.vault, required this.onRestored});

  /// The Vault as the bridge lists it (fields, snippets, combos).
  final Map<String, dynamic> vault;
  final VoidCallback onRestored;

  @override
  State<ArkivBackupCard> createState() => _ArkivBackupCardState();
}

class _ArkivBackupCardState extends State<ArkivBackupCard> {
  int? _onArkiv;
  BigInt? _gas;
  String? _owner;
  String? _status;
  String? _tx;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final k = await ArkivVault.keys();
      final entities = await ArkivVault.restoreEntities(k);
      final gas = await EvmRpc.balance(ArkivVault.chain, k.owner);
      if (!mounted) return;
      setState(() {
        _owner = k.owner;
        _onArkiv = entities.length;
        _gas = gas;
      });
    } on Exception {
      if (mounted) setState(() => _status = 'Arkiv can’t be reached right now');
    }
  }

  Future<void> _backUp() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final r = await ArkivVault.backUp(widget.vault);
      _tx = r.txHash;
      _status = r.txHash == null
          ? 'Already up to date'
          : [
              if (r.written > 0) '${r.written} saved',
              if (r.removed > 0) '${r.removed} removed',
            ].join(' · ');
      HapticFeedback.mediumImpact();
    } on Exception catch (e) {
      _status = '$e'.contains('OutOfFunds') || '$e'.toLowerCase().contains('insufficient')
          ? 'The backup key needs Arkiv test GLM for gas'
          : '$e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _load();
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final items = await ArkivVault.restore();
      var n = 0;
      for (final item in items) {
        switch (item['type']) {
          case 'field':
            await GlyfBridge.vaultUpsertField(
              id: (item['id'] as String).substring('field:'.length),
              kind: item['kind'] as String? ?? 'other',
              label: item['label'] as String? ?? '',
              value: item['value'] as String? ?? '',
            );
            n++;
          case 'snippet':
            await GlyfBridge.vaultUpsertSnippet(trigger: item['trigger'] as String, text: item['text'] as String? ?? '');
            n++;
          case 'combo':
            await GlyfBridge.vaultUpsertCombo(
              id: (item['id'] as String).substring('combo:'.length),
              label: item['label'] as String? ?? '',
              fieldIds: ((item['fieldIds'] as List?) ?? const []).cast<String>(),
            );
            n++;
        }
      }
      _status = n == 0 ? 'Nothing on Arkiv yet' : '$n restored';
      widget.onRestored();
    } on Exception catch (e) {
      _status = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final noGas = _gas != null && _gas == BigInt.zero;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.cloud_done_outlined, color: Glass.accent, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Arkiv',
                      style: TextStyle(color: Glass.ink, fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Semantics(
                    identifier: 'arkiv:status',
                    child: Text(
                      _status ??
                          (_onArkiv == null
                              ? 'Checking…'
                              : _onArkiv == 0
                                  ? 'Not backed up yet'
                                  : '$_onArkiv encrypted on Arkiv'),
                      style: const TextStyle(color: Glass.inkSoft, fontSize: 12),
                    ),
                  ),
                ]),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Glass.inkSoft)),
                )
              else ...[
                Semantics(
                  identifier: 'arkiv:restore',
                  button: true,
                  child: TextButton(
                    onPressed: (_onArkiv ?? 0) > 0 ? _restore : null,
                    child: const Text('Restore', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ),
                Semantics(
                  identifier: 'arkiv:backup',
                  button: true,
                  child: TextButton(
                    onPressed: noGas ? null : _backUp,
                    child: const Text('Back up',
                        style: TextStyle(color: Glass.accent, fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ]),
            if (noGas && _owner != null)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 4, right: 8),
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _owner!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup address copied')));
                  },
                  child: Text(
                    'Needs Arkiv test GLM · ${_owner!.substring(0, 6)}…${_owner!.substring(_owner!.length - 4)}',
                    style: const TextStyle(color: Glass.warning, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            if (_tx != null)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 2),
                child: GestureDetector(
                  onTap: () => GlyfBridge.openURL(ArkivVault.chain.txUrl(_tx!)),
                  child: const Text('View on the Arkiv explorer',
                      style: TextStyle(color: Glass.ink, fontSize: 12, decoration: TextDecoration.underline)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
