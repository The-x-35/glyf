import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/dismiss_keyboard.dart';
import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// The vault: the details, notes and shorthand the keyboard types for you.
/// Add and edit live in the app only; the keyboard just picks and types.
/// Validation (secrets are refused) runs native-side and surfaces here.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  Map<String, dynamic> _vault = {'fields': [], 'snippets': []};
  List<Map<String, dynamic>> _notes = [];

  /// Kinds the keyboard knows how to offer, by the name a person uses.
  static const kinds = <(String, String, IconData)>[
    ('name', 'Name', Icons.person_outline),
    ('email', 'Email', Icons.alternate_email),
    ('phone', 'Phone', Icons.phone_outlined),
    ('address', 'Address', Icons.home_outlined),
    ('wallet', 'Wallet address', Icons.account_balance_wallet_outlined),
    ('link', 'Link', Icons.link),
    ('social', 'Social', Icons.alternate_email),
    ('bio', 'Bio', Icons.short_text),
    ('custom', 'Other', Icons.label_outline),
  ];

  static IconData _iconFor(String? kind) =>
      kinds.firstWhere((k) => k.$1 == kind, orElse: () => kinds.last).$3;

  /// Its label, or its kind's name when it has none: a detail saved without
  /// a label showed a blank line above its value.
  static String _titleFor(Map f) {
    final own = ((f['label'] as String?) ?? '').trim();
    if (own.isNotEmpty) return own;
    return kinds.firstWhere((k) => k.$1 == f['kind'], orElse: () => kinds.last).$2;
  }

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
    final notes = await GlyfBridge.notesList();
    if (!mounted) return;
    setState(() {
      if (raw != null) _vault = jsonDecode(raw) as Map<String, dynamic>;
      _notes = notes;
    });
  }

  List<dynamic> get _fields => (_vault['fields'] as List?) ?? [];
  List<dynamic> get _snippets => (_vault['snippets'] as List?) ?? [];
  List<dynamic> get _images => (_vault['images'] as List?) ?? [];

  /// The system picker runs out of process, so nothing here asks for photo
  /// access — the app is handed the one picture and never sees the library.
  Future<void> _addImage() async {
    final res = await GlyfBridge.vaultPickImage();
    if (!mounted) return;
    if (!res.ok && res.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.error!)));
    }
    if (res.ok) _refresh();
  }

  Widget _imageTile(Map<String, dynamic> img) {
    final id = img['id'] as String? ?? '';
    return GestureDetector(
      onLongPress: () async {
        await GlyfBridge.vaultDeleteImage(id);
        _refresh();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<Uint8List?>(
          future: GlyfBridge.vaultImageData(id),
          builder: (_, snap) {
            final bytes = snap.data;
            if (bytes == null) {
              return Container(color: Glass.card);
            }
            return Image.memory(bytes, fit: BoxFit.cover);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboard(child: Scaffold(
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
              ]),
              const SizedBox(height: 14),

              _sectionHeader('Details', onAdd: () => _editField(null)),
              for (final f in _fields)
                _row(
                  title: _titleFor(f as Map),
                  subtitle: f['value'] as String? ?? '',
                  icon: _iconFor(f['kind'] as String?),
                  onTap: () => _editField(f as Map<String, dynamic>),
                  onDelete: () async {
                    await GlyfBridge.vaultDeleteField(f['id'] as String);
                    _refresh();
                  },
                ),
              if (_fields.isEmpty) _addRow('Add your address', () => _editField(null)),

              const SizedBox(height: 18),
              _sectionHeader('Notes', onAdd: () => _editNote(null)),
              for (final n in _notes)
                _row(
                  title: (n['text'] as String? ?? '').split('\n').first,
                  subtitle: (n['text'] as String? ?? '').contains('\n')
                      ? (n['text'] as String).split('\n').skip(1).join(' ')
                      : '',
                  icon: Icons.sticky_note_2_outlined,
                  onTap: () => _editNote(n),
                  onDelete: () async {
                    await GlyfBridge.notesDelete(n['id'] as String? ?? '');
                    _refresh();
                  },
                ),
              if (_notes.isEmpty) _addRow('Add a note', () => _editNote(null)),

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
              if (_snippets.isEmpty) _addRow('Add shorthand', () => _editSnippet(null)),

              const SizedBox(height: 18),
              _sectionHeader('Images', onAdd: _addImage),
              if (_images.isNotEmpty)
                GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final img in _images)
                      _imageTile(img as Map<String, dynamic>),
                  ],
                ),
              if (_images.isEmpty) _addRow('Keep an image', _addImage),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _sectionHeader(String title, {VoidCallback? onAdd}) {
    return Row(children: [
      Text(title,
          style: const TextStyle(
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

  /// An empty section is one quiet tap target, not a paragraph.
  Widget _addRow(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        onTap: onTap,
        child: Row(children: [
          const Icon(Icons.add_circle_outline, color: Glass.inkSoft, size: 18),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Glass.inkSoft, fontSize: 14.5)),
        ]),
      ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Glass.ink, fontSize: 14.5, fontWeight: FontWeight.w600)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 12)),
            ]),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: Color(0xFFA6ABB4), size: 18),
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
    if (!kinds.any((k) => k.$1 == kind)) kind = 'custom';
    await _sheet(
      title: existing == null ? 'Add detail' : 'Edit detail',
      builder: (setSheetState, showError) => [
        DropdownButtonFormField<String>(
          initialValue: kind,
          dropdownColor: Colors.white,
          decoration: _dec('Type'),
          style: const TextStyle(color: Glass.ink),
          items: [
            for (final k in kinds) DropdownMenuItem(value: k.$1, child: Text(k.$2)),
          ],
          onChanged: (v) => kind = v ?? 'custom',
        ),
        const SizedBox(height: 10),
        Semantics(
          identifier: 'vault-label-field',
          child: TextField(
              controller: labelCtl,
              style: const TextStyle(color: Glass.ink),
              decoration: _dec('Label, like Home')),
        ),
        const SizedBox(height: 10),
        Semantics(
          identifier: 'vault-value-field',
          child: TextField(
              controller: valueCtl,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: Glass.ink),
              decoration: _dec('Value')),
        ),
      ],
      onSave: () async {
        final res = await GlyfBridge.vaultUpsertField(
          id: existing?['id'] as String?,
          kind: kind,
          // No label typed: the kind's own name ("Address") stands in.
          label: labelCtl.text.trim().isNotEmpty
              ? labelCtl.text.trim()
              : kinds.firstWhere((k) => k.$1 == kind, orElse: () => kinds.last).$2,
          value: valueCtl.text.trim(),
        );
        if (res.ok) Telemetry.log('vault_field_saved', {'kind': kind});
        return res;
      },
    );
  }

  Future<void> _editNote(Map<String, dynamic>? note) async {
    final textCtl = TextEditingController(text: note?['text'] as String? ?? '');
    await _sheet(
      title: note == null ? 'New note' : 'Edit note',
      builder: (setSheetState, showError) => [
        TextField(
          controller: textCtl,
          maxLines: 6,
          minLines: 3,
          autofocus: note == null,
          style: const TextStyle(color: Glass.ink, fontSize: 15),
          decoration: _dec('Note'),
        ),
      ],
      onSave: () async {
        final res = await GlyfBridge.notesUpsert(
            id: note?['id'] as String?, text: textCtl.text);
        if (res.ok) Telemetry.log(note == null ? 'note_created' : 'note_edited');
        return res;
      },
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
            // A trigger is typed exactly: nothing may correct or expand it
            // ("omw" would come back as "On my way!").
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.visiblePassword,
            style: const TextStyle(color: Glass.ink),
            decoration: _dec('Shortcut, like ;sig')),
        const SizedBox(height: 10),
        TextField(
            controller: textCtl,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(color: Glass.ink),
            decoration: _dec('Types out')),
      ],
      onSave: () => GlyfBridge.vaultUpsertSnippet(
          trigger: trigCtl.text.trim(), text: textCtl.text.trim()),
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFB6BAC3), fontSize: 13.5),
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
                  icon: const Icon(Icons.close, color: Glass.inkSoft, size: 20),
                ),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
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
