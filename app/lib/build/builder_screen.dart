import 'package:flutter/material.dart';

import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../profile/paywall_sheet.dart';
import 'key_picker.dart';

/// §6.8 — the Builder. Describe → generated def (steps visible, prompts
/// editable) → test on sample text → save → bind to a key. The def is the
/// server's strict Builder format; nothing runs client-side.
class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key});

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  final _describe = TextEditingController();
  final _name = TextEditingController();
  final _testInput = TextEditingController(
      text: 'hey can u send the report tmrw morning thx');

  Map<String, dynamic>? _def;
  bool _generating = false;
  bool _testing = false;
  bool _saving = false;
  String? _error;
  String _testResult = '';
  int _toolTab = 0; // 0 = Apps, 1 = Tools
  String? _expandedApp;
  Map<String, dynamic> _connectors = {};

  static const _examples = [
    'Turn my rant into a calm, professional reply',
    'Summarize into 3 bullets with emoji',
    'Answer with today’s weather for the city I typed',
    'Rewrite as a LinkedIn post with a hook',
  ];

  /// The connectable apps and what each offers once its OAuth lands.
  static const _apps = [
    ('google', 'Google Calendar', '📅',
        ['Read today’s events', 'Drop events into your text',
         'Check availability']),
    ('google', 'Gmail', '✉️',
        ['Create draft emails', 'Read email content']),
    ('google', 'Google Meet', '🎥',
        ['Create meetings', 'View meeting details']),
    ('notion', 'Notion', '📄',
        ['Search and read pages', 'Add and update content']),
    ('slack', 'Slack', '💬',
        ['Send messages', 'View channels', 'Search messages']),
    ('github', 'GitHub', '🐙',
        ['Read issues and PRs', 'Paste repo links with context']),
    ('linear', 'Linear', '📐',
        ['Read and create issues', 'Paste ticket links']),
    ('todoist', 'Todoist', '☑️',
        ['Read today’s tasks', 'Add tasks from your text']),
    ('calendly', 'Calendly', '🗓️',
        ['Generate booking links', 'Check availability']),
    ('zoom', 'Zoom', '📹',
        ['Create meeting links']),
    ('spotify', 'Spotify', '🎵',
        ['Share what you’re playing']),
  ];

  /// Live today — the keyless registry, no login needed.
  static const _tools = [
    ('⛅', 'Weather'), ('🌫️', 'Air quality'), ('📈', 'Crypto price'),
    ('💹', 'Stocks'), ('💱', 'FX convert'), ('📖', 'Dictionary'),
    ('🔤', 'Synonyms'), ('🌍', 'Wikipedia'), ('📍', 'Place search'),
    ('🚗', 'Route ETA'), ('🎉', 'Holidays'), ('📚', 'Books'),
    ('📰', 'Tech news'), ('⚽', 'Fixtures'), ('🍳', 'Recipes'),
    ('🔗', 'Link preview'), ('🕐', 'Time zones'), ('😄', 'Dad jokes'),
    ('✨', 'Quotes'), ('💡', 'Advice'), ('🎲', 'Facts'),
    ('🗣️', 'Slang'), ('🌏', 'Countries'), ('🐙', 'GitHub repos'),
    ('🥗', 'Food facts'),
  ];

  @override
  void initState() {
    super.initState();
    GlyfApi.connectorsStatus().then((s) {
      if (mounted) setState(() => _connectors = s);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _describe.dispose();
    _name.dispose();
    _testInput.dispose();
    super.dispose();
  }

  bool _appConfigured(String providerId) {
    final providers =
        (_connectors['providers'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    return providers
        .any((p) => p['id'] == providerId && p['configured'] == true);
  }

  Future<void> _generate() async {
    final desc = _describe.text.trim();
    if (desc.length < 4 || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
      _def = null;
      _testResult = '';
    });
    Telemetry.log('builder_generate');
    try {
      final def = await GlyfApi.builderGenerate(desc);
      _name.text = (def['name'] as String?) ?? 'My glyf';
      setState(() => _def = def);
      Telemetry.log('builder_generated_ok');
    } on GlyfApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() =>
          _error = 'Couldn’t reach the Glyf server — is it running?');
    } finally {
      setState(() => _generating = false);
    }
  }

  Future<void> _test() async {
    final def = _def;
    if (def == null || _testing) return;
    setState(() {
      _testing = true;
      _error = null;
      _testResult = '';
    });
    try {
      final text = await GlyfApi.builderTest(def, _testInput.text);
      setState(() => _testResult = text);
      Telemetry.log('builder_tested');
    } on GlyfApiException catch (e) {
      if (e.capHit && mounted) {
        final unlocked = await showPaywall(context, reason: 'cap');
        if (unlocked) return _test();
      }
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Test failed — server unreachable');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveAndBind() async {
    final def = _def;
    if (def == null || _saving) return;
    def['name'] = _name.text.trim().isEmpty ? 'My glyf' : _name.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await GlyfApi.saveGlyf(def);
      final id = (saved['id'] as String?) ?? (def['id'] as String? ?? '');
      Telemetry.log('builder_saved');
      if (!mounted) return;
      final letter = await pickKey(context,
          title: 'Bind “${def['name']}” to…');
      if (letter != null && id.isNotEmpty) {
        await bindGlyf(
            letter: letter, glyfId: id, displayName: def['name'] as String);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Hold ${letter.toUpperCase()} fires ${def['name']}')));
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } on GlyfApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Save failed — server unreachable');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Edit an llm prompt / format template in place — the def stays honest to
  /// what will actually run (§6.8: users may inspect and tweak steps).
  Future<void> _editStep(int index) async {
    final def = _def;
    if (def == null) return;
    final steps = (def['steps'] as List).cast<Map<String, dynamic>>();
    final step = steps[index];
    final key = step['type'] == 'format' ? 'template' : 'prompt';
    if (step[key] == null) return;
    final ctrl = TextEditingController(text: step[key] as String);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Edit ${step['type']} step',
              style: const TextStyle(
                  color: Glass.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            maxLines: 8,
            style: const TextStyle(
                fontSize: 13, fontFamily: 'Menlo', color: Glass.ink),
            decoration: _fieldDecoration(''),
          ),
          const SizedBox(height: 12),
          PillButton(label: 'Done', onPressed: () => Navigator.pop(ctx, true)),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (saved == true) {
      setState(() {
        step[key] = ctrl.text;
        _testResult = '';
      });
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Glass.ink),
            onPressed: () => Navigator.of(context).pop()),
        title: const Text('Builder',
            style: TextStyle(
                color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
          children: [
            const Text('What do you want?',
                style: TextStyle(
                    color: Glass.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'builder:describe',
              textField: true,
              child: TextField(
                controller: _describe,
                maxLines: 4,
                minLines: 3,
                maxLength: 600,
                style: const TextStyle(color: Glass.ink, fontSize: 15),
                decoration: _fieldDecoration(
                    'e.g. Translate what I type into Spanish.\n'
                    'e.g. Fix my grammar and make it professional.'),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in _examples)
                GestureDetector(
                  onTap: () => setState(() => _describe.text = e),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F3F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(e,
                        style: const TextStyle(
                            color: Glass.inkSoft, fontSize: 11.5)),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Semantics(
              identifier: 'builder:generate',
              button: true,
              child: PillButton(
                label: _generating ? 'Designing your Glyf…' : 'Generate',
                onPressed: _generating ? () {} : _generate,
              ),
            ),
            if (_def == null) ...[
              const SizedBox(height: 26),
              const Text('Available tools',
                  style: TextStyle(
                      color: Glass.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text('Glyf picks the right ones from your description',
                  style: TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  for (final (i, label) in const ['Apps', 'Tools'].indexed)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _toolTab = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _toolTab == i
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _toolTab == i
                                ? const [
                                    BoxShadow(
                                        color: Color(0x14000000),
                                        blurRadius: 4,
                                        offset: Offset(0, 1))
                                  ]
                                : null,
                          ),
                          child: Text(label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: _toolTab == i
                                      ? Glass.ink
                                      : Glass.inkSoft,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _toolTab == 0
                    ? Column(
                        key: const ValueKey('apps'),
                        children: [
                          for (final (provider, name, emoji, actions) in _apps)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                onTap: () => setState(() => _expandedApp =
                                    _expandedApp == name ? null : name),
                                child: Column(children: [
                                  Row(children: [
                                    Text(emoji,
                                        style:
                                            const TextStyle(fontSize: 20)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(name,
                                          style: const TextStyle(
                                              color: Glass.ink,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    Text(
                                        _appConfigured(provider)
                                            ? 'Ready'
                                            : 'Soon',
                                        style: TextStyle(
                                            color: _appConfigured(provider)
                                                ? Glass.success
                                                : Glass.inkSoft,
                                            fontSize: 12)),
                                    const SizedBox(width: 6),
                                    AnimatedRotation(
                                      turns:
                                          _expandedApp == name ? 0.5 : 0,
                                      duration: const Duration(
                                          milliseconds: 180),
                                      child: const Icon(
                                          Icons.keyboard_arrow_down,
                                          size: 18,
                                          color: Color(0xFFB9BEC7)),
                                    ),
                                  ]),
                                  AnimatedCrossFade(
                                    duration:
                                        const Duration(milliseconds: 200),
                                    crossFadeState: _expandedApp == name
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    firstChild: const SizedBox(
                                        width: double.infinity),
                                    secondChild: Padding(
                                      padding:
                                          const EdgeInsets.only(top: 10),
                                      child: Column(children: [
                                        for (final a in actions)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(
                                                    bottom: 5),
                                            child: Row(children: [
                                              const Icon(Icons.check,
                                                  size: 13,
                                                  color: Glass.inkSoft),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(a,
                                                    style: const TextStyle(
                                                        color:
                                                            Glass.inkSoft,
                                                        fontSize: 12.5)),
                                              ),
                                            ]),
                                          ),
                                      ]),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                        ],
                      )
                    : Wrap(
                        key: const ValueKey('tools'),
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (emoji, name) in _tools)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Glass.hairline),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(emoji,
                                        style:
                                            const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 7),
                                    Text(name,
                                        style: const TextStyle(
                                            color: Glass.ink,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600)),
                                  ]),
                            ),
                        ],
                      ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF2F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFC03A2E), fontSize: 13)),
              ),
            ],
            if (def != null) ...[
              const SizedBox(height: 24),
              const Text('Your Glyf',
                  style: TextStyle(
                      color: Glass.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'builder:name',
                textField: true,
                child: TextField(
                  controller: _name,
                  maxLength: 28,
                  style: const TextStyle(
                      color: Glass.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                  decoration: _fieldDecoration('Name'),
                ),
              ),
              const SizedBox(height: 8),
              for (final (i, step) in (def['steps'] as List)
                  .cast<Map<String, dynamic>>()
                  .indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () => _editStep(i),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF17181C),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                                (step['type'] as String).toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          Text('step ${i + 1}',
                              style: const TextStyle(
                                  color: Glass.inkSoft, fontSize: 11.5)),
                          const Spacer(),
                          if (step['prompt'] != null ||
                              step['template'] != null)
                            const Icon(Icons.edit_outlined,
                                size: 15, color: Glass.inkSoft),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          (step['prompt'] ??
                                  step['template'] ??
                                  (step['type'] == 'tool'
                                      ? 'tool: ${step['tool']}'
                                      : step['cond'] ?? '')) as String,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Glass.ink,
                              fontSize: 12,
                              fontFamily: 'Menlo',
                              height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.remove_red_eye_outlined,
                    size: 14, color: Glass.inkSoft),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sees: ${((def['discloses'] as List?) ?? []).join(' · ')}',
                    style:
                        const TextStyle(color: Glass.inkSoft, fontSize: 12),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              const Text('Test',
                  style: TextStyle(
                      color: Glass.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'builder:test-input',
                textField: true,
                child: TextField(
                  controller: _testInput,
                  maxLines: 2,
                  style: const TextStyle(color: Glass.ink, fontSize: 14),
                  decoration: _fieldDecoration('Sample text to run it on'),
                ),
              ),
              const SizedBox(height: 10),
              Semantics(
                identifier: 'builder:test',
                button: true,
                child: OutlinedButton(
                  onPressed: _testing ? null : _test,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: Glass.ink),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(23)),
                  ),
                  child: Text(_testing ? 'Running…' : 'Run a test',
                      style: const TextStyle(
                          color: Glass.ink, fontWeight: FontWeight.w700)),
                ),
              ),
              if (_testResult.isNotEmpty) ...[
                const SizedBox(height: 10),
                Semantics(
                  identifier: 'builder:test-result',
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F3F7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_testResult,
                        style: const TextStyle(
                            color: Glass.ink, fontSize: 14, height: 1.4)),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Semantics(
                identifier: 'builder:save',
                button: true,
                child: PillButton(
                  label: _saving ? 'Saving…' : 'Save & bind to a key',
                  onPressed: _saving ? () {} : _saveAndBind,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFB6BAC3), fontSize: 13.5),
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Glass.hairline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Glass.accent, width: 1.4)),
      );
}
