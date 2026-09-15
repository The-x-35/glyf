import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// Notes — write here, drop into any field from the keyboard (hold N, or
/// Glyf → Notes). Secrets are refused on save, same rules as the vault.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Map<String, dynamic>> _notes = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final notes = await GlyfBridge.notesList();
    if (mounted) setState(() => _notes = notes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Glass.ink),
            onPressed: () => Navigator.of(context).pop()),
        title: const Text('Notes',
            style: TextStyle(
                color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Glass.ink),
            onPressed: () => _edit(null),
          ),
        ],
      ),
      body: SafeArea(
        child: _notes.isEmpty
            ? Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('📝', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 10),
                      Text('Notes you write here show up\ninside your keyboard',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Glass.inkSoft,
                              fontSize: 14,
                              height: 1.5)),
                    ]),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                children: [
                  for (final n in _notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        onTap: () => _edit(n),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Expanded(
                            child: Text(n['text'] as String? ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Glass.ink,
                                    fontSize: 14.5,
                                    height: 1.35)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 19, color: Color(0xFFC03A2E)),
                            onPressed: () async {
                              await GlyfBridge.notesDelete(
                                  n['id'] as String? ?? '');
                              _refresh();
                            },
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(Map<String, dynamic>? note) async {
    final ctrl = TextEditingController(text: note?['text'] as String? ?? '');
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text(note == null ? 'New note' : 'Edit note',
                  style: const TextStyle(
                      color: Glass.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final res = await GlyfBridge.notesUpsert(
                      id: note?['id'] as String?, text: ctrl.text);
                  if (res.ok) {
                    Telemetry.log(note == null ? 'note_created' : 'note_edited');
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } else {
                    setSheet(() => error = res.error);
                  }
                },
                child: const Text('Save',
                    style: TextStyle(
                        color: Glass.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Glass.inkSoft),
                  onPressed: () => Navigator.of(ctx).pop()),
            ]),
            TextField(
              controller: ctrl,
              maxLines: 6,
              minLines: 3,
              autofocus: true,
              style: const TextStyle(color: Glass.ink, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Write it once, insert it anywhere',
                hintStyle:
                    const TextStyle(color: Color(0xFFB6BAC3), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF7F8FA),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFC03A2E), fontSize: 13)),
              ),
            const SizedBox(height: 6),
          ]),
        ),
      ),
    );
    ctrl.dispose();
    _refresh();
  }
}
