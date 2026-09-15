import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// §6.7 vault editor — add/edit lives in the APP only; the keyboard just
/// picks and types. Validation (blocked types) runs native-side; refusals
/// surface verbatim here.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  Map<String, dynamic> _vault = {'fields': [], 'combos': [], 'snippets': []};

  static const kinds = [
    'name', 'email', 'phone', 'address', 'upi', 'gst', 'wallet',
    'link', 'social', 'bio', 'reply', 'custom',
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
    // UI-test hook: opens the field form pre-filled with a card number so the
    // refusal path is verifiable without typing (typing summons the keyboard,
    // whose sheet-lift breaks XCUITest frame math on Flutter modals).
    GlyfBridge.launchArgs().then((args) {
      if (args.contains('--glyf-test-prefill-card') && mounted) {
        _editField({'kind': 'custom', 'label': 'Visa', 'value': '4242 4242 4242 4242'});
      }
    });
  }

  Future<void> _refresh() async {
    final raw = await GlyfBridge.vaultList();
    if (!mounted || raw == null) return;
    setState(() => _vault = jsonDecode(raw) as Map<String, dynamic>);
  }

  List<dynamic> get _fields => (_vault['fields'] as List?) ?? [];
  List<dynamic> get _combos => (_vault['combos'] as List?) ?? [];
  List<dynamic> get _snippets => (_vault['snippets'] as List?) ?? [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlyfBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.chevron_left, color: Glass.ink),
                ),
                const Text('Vault',
                    style: TextStyle(
                        color: Glass.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
              ]),
              const SizedBox(height: 4),
              Text(
                'Long-press S on the keyboard to type any of this. '
                'Passwords, cards, IDs, and seeds are refused by design.',
                style: TextStyle(
                    color: Glass.inkSoft, fontSize: 12.5),
              ),
              const SizedBox(height: 16),

              _sectionHeader('Fields', onAdd: () => _editField(null)),
              for (final f in _fields)
                _row(
                  title: f['label'] as String? ?? '',
                  subtitle: f['value'] as String? ?? '',
                  icon: Icons.badge_outlined,
                  onTap: () => _editField(f as Map<String, dynamic>),
                  onDelete: () async {
                    await GlyfBridge.vaultDeleteField(f['id'] as String);
                    _refresh();
                  },
                ),
              if (_fields.isEmpty) _empty('No fields yet — add your address, UPI, links…'),

              const SizedBox(height: 18),
              _sectionHeader('Combos', onAdd: _fields.isEmpty ? null : _editCombo),
              for (final c in _combos)
                _row(
                  title: c['label'] as String? ?? '',
                  subtitle: '${(c['fieldIds'] as List?)?.length ?? 0} fields · one tap',
                  icon: Icons.layers_outlined,
                  onTap: null,
                  onDelete: () async {
                    await GlyfBridge.vaultDeleteCombo(c['id'] as String);
                    _refresh();
                  },
                ),
              if (_combos.isEmpty)
                _empty('Combos type several fields at once — “Shipping block”'),

              const SizedBox(height: 18),
              _sectionHeader('Shorthand', onAdd: () => _editSnippet(null)),
              for (final s in _snippets)
                _row(
                  title: s['trigger'] as String? ?? '',
                  subtitle: s['text'] as String? ?? '',
                  icon: Icons.bolt_outlined,
                  onTap: () => _editSnippet(s as Map<String, dynamic>),
                  onDelete: () async {
                    await GlyfBridge.vaultDeleteSnippet(s['trigger'] as String);
                    _refresh();
                  },
                ),
              if (_snippets.isEmpty)
                _empty('Type ;sig anywhere and it expands inline'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onAdd}) {
    return Row(children: [
      Text(title,
          style: TextStyle(
              color: Glass.inkSoft,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3)),
      const Spacer(),
      if (onAdd != null)
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 16, color: Glass.accent),
          label: const Text('Add',
              style: TextStyle(color: Glass.accent, fontSize: 13)),
        ),
    ]);
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text,
          style: TextStyle(
              color: const Color(0xFFB6BAC3), fontSize: 12.5)),
    );
  }

  Widget _row({
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
    required VoidCallback onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: Glass.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: Glass.ink, fontSize: 14.5, fontWeight: FontWeight.w600)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Glass.inkSoft, fontSize: 12)),
            ]),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline,
                color: const Color(0xFFA6ABB4), size: 18),
          ),
        ]),
      ),
    );
  }

  // MARK: editors

  Future<void> _editField(Map<String, dynamic>? existing) async {
    final labelCtl = TextEditingController(text: existing?['label'] as String? ?? '');
    final valueCtl = TextEditingController(text: existing?['value'] as String? ?? '');
    var kind = existing?['kind'] as String? ?? 'address';
    await _sheet(
      title: existing == null ? 'Add field' : 'Edit field',
      builder: (setSheetState, showError) => [
        DropdownButtonFormField<String>(
          initialValue: kind,
          dropdownColor: Colors.white,
          decoration: _dec('Type'),
          style: TextStyle(color: Glass.ink),
          items: [
            for (final k in kinds)
              DropdownMenuItem(value: k, child: Text(k)),
          ],
          onChanged: (v) => kind = v ?? 'custom',
        ),
        const SizedBox(height: 10),
        Semantics(
          identifier: 'vault-label-field',
          child: TextField(
              controller: labelCtl,
              style: TextStyle(color: Glass.ink),
              decoration: _dec('Label — e.g. Home address')),
        ),
        const SizedBox(height: 10),
        Semantics(
          identifier: 'vault-value-field',
          child: TextField(
              controller: valueCtl,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(color: Glass.ink),
              decoration: _dec('Value')),
        ),
      ],
      onSave: () async {
        final res = await GlyfBridge.vaultUpsertField(
          id: existing?['id'] as String?,
          kind: kind,
          label: labelCtl.text.trim(),
          value: valueCtl.text.trim(),
        );
        if (res.ok) Telemetry.log('vault_field_saved', {'kind': kind});
        return res;
      },
    );
  }

  Future<void> _editCombo() async {
    final labelCtl = TextEditingController();
    final selected = <String>{};
    await _sheet(
      title: 'New combo',
      builder: (setSheetState, showError) => [
        TextField(
            controller: labelCtl,
            style: TextStyle(color: Glass.ink),
            decoration: _dec('Label — e.g. Shipping block')),
        const SizedBox(height: 10),
        for (final f in _fields)
          CheckboxListTile(
            dense: true,
            activeColor: Glass.accent,
            checkColor: Colors.white,
            title: Text(f['label'] as String? ?? '',
                style: TextStyle(color: Glass.ink, fontSize: 14)),
            value: selected.contains(f['id']),
            onChanged: (v) => setSheetState(() {
              v == true ? selected.add(f['id'] as String) : selected.remove(f['id']);
            }),
          ),
      ],
      onSave: () => GlyfBridge.vaultUpsertCombo(
          label: labelCtl.text.trim(), fieldIds: selected.toList()),
    );
  }

  Future<void> _editSnippet(Map<String, dynamic>? existing) async {
    final trigCtl = TextEditingController(text: existing?['trigger'] as String? ?? ';');
    final textCtl = TextEditingController(text: existing?['text'] as String? ?? '');
    await _sheet(
      title: existing == null ? 'Add shorthand' : 'Edit shorthand',
      builder: (setSheetState, showError) => [
        TextField(
            controller: trigCtl,
            style: TextStyle(color: Glass.ink),
            decoration: _dec('Trigger — like ;sig')),
        const SizedBox(height: 10),
        TextField(
            controller: textCtl,
            maxLines: 3,
            minLines: 1,
            style: TextStyle(color: Glass.ink),
            decoration: _dec('Expands to…')),
      ],
      onSave: () => GlyfBridge.vaultUpsertSnippet(
          trigger: trigCtl.text.trim(), text: textCtl.text.trim()),
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: const Color(0xFFB6BAC3), fontSize: 13.5),
      filled: true,
      fillColor: const Color(0xFFF2F3F7),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  Future<void> _sheet({
    required String title,
    required List<Widget> Function(
            void Function(void Function()) setSheetState, void Function(String) showError)
        builder,
    required Future<({bool ok, String? error})> Function() onSave,
  }) async {
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // A form sheet: accidental barrier taps must not eat the user's input.
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Save lives in the header so it stays reachable above the
              // keyboard while a field is being typed.
              Row(children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  icon: Icon(Icons.close,
                      color: Glass.inkSoft, size: 20),
                ),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                Semantics(
                  identifier: 'vault-save',
                  child: TextButton(
                    onPressed: () async {
                      final res = await onSave();
                      if (res.ok) {
                        if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                        _refresh();
                      } else {
                        setSheetState(() => error = res.error ?? 'Could not save');
                      }
                    },
                    child: const Text('Save',
                        style: TextStyle(
                            color: Glass.accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error!,
                      key: const Key('vault-error'),
                      style: const TextStyle(color: Glass.danger, fontSize: 13)),
                ),
              ...builder(setSheetState, (e) => setSheetState(() => error = e)),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
