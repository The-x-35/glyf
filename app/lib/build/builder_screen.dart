import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/catalog.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/text_sheet.dart';
import '../core/theme.dart';
import '../home/keyboard_visual.dart';
import '../profile/paywall_sheet.dart';
import 'key_picker.dart';

/// §6.8 — make a glyf. Say what it should do (or tap an idea), watch it work
/// on a sample message, pick the key it lives on, save. The generated steps
/// stay one tap away under "How it works"; nothing runs client-side.
class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key, this.initialKey});

  /// The key it was started from (Home's key sheet), picked in advance.
  final String? initialKey;

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  final _describe = TextEditingController();
  final _name = TextEditingController();
  final _sample = TextEditingController(
      text: 'hey can u send the report tmrw morning thx');

  Map<String, dynamic>? _def;
  Map<String, String> _bindings = {};
  String? _key;
  bool _generating = false;
  bool _testing = false;
  bool _saving = false;
  bool _showSteps = false;
  bool _editingSample = false;
  String? _error;
  String _result = '';

  /// Tap one and it is made: no typing needed.
  static const _ideas = [
    ('💼', 'Turn it into a LinkedIn post'),
    ('😊', 'Make it sound warmer'),
    ('📝', 'Sum it up in 3 bullets'),
    ('📧', 'Turn my notes into an email'),
    ('🌶️', 'Reply in Hinglish'),
    ('🙏', 'Say no, politely'),
  ];

  @override
  void initState() {
    super.initState();
    _key = widget.initialKey;
    _describe.addListener(() => setState(() {}));
    GlyfBridge.sharedSettings().then((s) {
      final b = (s['bindings'] as Map<String, dynamic>?) ?? {};
      if (mounted) {
        setState(() => _bindings = b.map((k, v) => MapEntry(k, v.toString())));
      }
    });
  }

  @override
  void dispose() {
    _describe.dispose();
    _name.dispose();
    _sample.dispose();
    super.dispose();
  }

  Future<void> _generate([String? idea]) async {
    if (idea != null) _describe.text = idea;
    final desc = _describe.text.trim();
    if (desc.length < 4 || _generating) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _generating = true;
      _error = null;
      _def = null;
      _result = '';
      _showSteps = false;
    });
    Telemetry.log('builder_generate');
    try {
      final def = await GlyfApi.builderGenerate(desc);
      _name.text = (def['name'] as String?) ?? 'My glyf';
      setState(() => _def = def);
      Telemetry.log('builder_generated_ok');
      _test();
    } on GlyfApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Couldn’t reach Glyf. Try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _test() async {
    final def = _def;
    if (def == null || _testing) return;
    setState(() {
      _testing = true;
      _error = null;
      _result = '';
    });
    try {
      final text = await GlyfApi.builderTest(def, _sample.text);
      if (mounted) setState(() => _result = text);
      Telemetry.log('builder_tested');
    } on GlyfApiException catch (e) {
      if (e.capHit && mounted) {
        final unlocked = await showPaywall(context, reason: 'cap');
        if (unlocked) {
          setState(() => _testing = false);
          return _test();
        }
      }
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t try it just now.');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
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
      final key = _key;
      if (key != null && id.isNotEmpty) {
        await bindGlyf(letter: key, glyfId: id, displayName: def['name'] as String);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(key == null
              ? '${def['name']} saved'
              : 'Hold ${key.toUpperCase()} to run ${def['name']}')));
      Navigator.of(context).pop(true);
    } on GlyfApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Couldn’t save. Try again.');
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
    final field = step['type'] == 'format' ? 'template' : 'prompt';
    if (step[field] == null) return;
    final text = await showTextSheet(
      context,
      title: 'Edit step',
      action: 'Done',
      initial: step[field] as String,
      maxLines: 8,
      autofocus: false,
      style: const TextStyle(fontSize: 14, color: Glass.ink, height: 1.35),
    );
    if (text != null && mounted) {
      setState(() => step[field] = text);
      _test();
    }
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('New glyf',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      bottomNavigationBar: def == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Semantics(
                  identifier: 'builder:save',
                  button: true,
                  child: PillButton(
                    label: _saving
                        ? 'Saving…'
                        : _key == null
                            ? 'Save'
                            : 'Save to ${_key!.toUpperCase()}',
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _composer(),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Glass.danger, fontSize: 13)),
          ],
          if (def == null && !_generating) ...[
            const SizedBox(height: 22),
            _label('Ideas'),
            _card([
              for (final (emoji, idea) in _ideas)
                _row(
                  leading: Text(emoji, style: const TextStyle(fontSize: 19)),
                  title: idea,
                  onTap: () => _generate(idea),
                ),
            ]),
          ],
          if (_generating) ...[
            const SizedBox(height: 22),
            const _Working(label: 'Making your glyf…'),
          ],
          if (def != null) ...[
            const SizedBox(height: 22),
            _label('Try it'),
            _preview(),
            const SizedBox(height: 22),
            _label('Hold a key to run it'),
            _keyPicker(),
            const SizedBox(height: 22),
            _howItWorks(def),
          ],
        ],
      ),
    );
  }

  // ── pieces ──────────────────────────────────────────────────────────────

  Widget _composer() {
    final ready = _describe.text.trim().length >= 4 && !_generating;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Glass.radiusCard),
        border: Border.all(color: Glass.hairline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Semantics(
            identifier: 'builder:describe',
            textField: true,
            child: TextField(
              controller: _describe,
              minLines: 1,
              maxLines: 5,
              maxLength: 600,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _generate(),
              style: const TextStyle(color: Glass.ink, fontSize: 16, height: 1.35),
              decoration: const InputDecoration(
                hintText: 'What should it do?',
                hintStyle: TextStyle(color: Color(0xFFA6ABB4), fontSize: 16),
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          identifier: 'builder:generate',
          button: true,
          child: GestureDetector(
            onTap: ready ? () => _generate() : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: ready ? Glass.pill : const Color(0xFFD9DBE0),
                shape: BoxShape.circle,
              ),
              child: _generating
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ),
      ]),
    );
  }

  /// The glyf at work on a sample message: the message, then what it
  /// becomes. Tap the message to try your own.
  Widget _preview() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Glass.radiusCard),
        border: Border.all(color: Glass.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          identifier: 'builder:name',
          textField: true,
          child: TextField(
            controller: _name,
            maxLength: 28,
            style: const TextStyle(
                color: Glass.ink, fontSize: 19, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              counterText: '',
              suffixIcon: Icon(Icons.edit_outlined, size: 16, color: Color(0xFFB9BEC7)),
              suffixIconConstraints: BoxConstraints(minWidth: 24),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => setState(() => _editingSample = true),
            child: _bubble(
              color: const Color(0xFFF1F2F5),
              child: _editingSample
                  ? TextField(
                      controller: _sample,
                      autofocus: true,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        setState(() => _editingSample = false);
                        _test();
                      },
                      style: const TextStyle(color: Glass.ink, fontSize: 15, height: 1.35),
                      decoration: const InputDecoration(
                          border: InputBorder.none, isDense: true),
                    )
                  : Text(_sample.text,
                      style: const TextStyle(
                          color: Glass.ink, fontSize: 15, height: 1.35)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: _bubble(
            color: Glass.pill,
            child: _testing
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)),
                    SizedBox(width: 10),
                    Text('Writing…',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                  ])
                : _result.isEmpty
                    // The test failed (the banner above says so): a spinner
                    // here would claim it is still writing. Offer the retry.
                    ? GestureDetector(
                        onTap: _test,
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
                          SizedBox(width: 8),
                          Text('Try again',
                              style: TextStyle(color: Colors.white70, fontSize: 15)),
                        ]),
                      )
                : Semantics(
                    identifier: 'builder:test-result',
                    child: Text(_result,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, height: 1.35)),
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _bubble({required Color color, required Widget child}) => ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: child,
        ),
      );

  Widget _keyPicker() {
    final key = _key;
    final taken = key == null ? null : _bindings[key];
    final shown = Map.of(_bindings);
    if (key != null) shown[key] = 'new';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Glass.radiusCard),
        border: Border.all(color: Glass.hairline),
      ),
      child: Column(children: [
        KeyboardVisual(
          bindings: shown,
          highlight: key,
          onKeyTap: (c) => setState(() => _key = _key == c ? null : c),
        ),
        if (key != null) ...[
          const SizedBox(height: 4),
          Text(
            taken == null
                ? 'Hold ${key.toUpperCase()} to run it'
                : 'Replaces ${Catalog.byId(taken).title} on ${key.toUpperCase()}',
            style: TextStyle(
                color: taken == null ? Glass.inkSoft : Glass.warning, fontSize: 13),
          ),
        ],
      ]),
    );
  }

  Widget _howItWorks(Map<String, dynamic> def) {
    final steps = (def['steps'] as List).cast<Map<String, dynamic>>();
    final sees = ((def['discloses'] as List?) ?? []).join(' · ');
    return _card([
      _row(
        leading: const Icon(Icons.tune_rounded, size: 20, color: Glass.ink),
        title: 'How it works',
        trailing: AnimatedRotation(
          turns: _showSteps ? 0.25 : 0,
          duration: const Duration(milliseconds: 160),
          child: const Icon(Icons.chevron_right, color: Color(0xFFB9BEC7)),
        ),
        onTap: () => setState(() => _showSteps = !_showSteps),
      ),
      if (_showSteps) ...[
        for (final (i, step) in steps.indexed)
          _row(
            leading: Text('${i + 1}',
                style: const TextStyle(
                    color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w700)),
            title: (step['prompt'] ??
                    step['template'] ??
                    (step['type'] == 'tool' ? 'Uses ${step['tool']}' : step['cond'] ?? ''))
                as String,
            maxLines: 3,
            trailing: step['prompt'] != null || step['template'] != null
                ? const Icon(Icons.edit_outlined, size: 16, color: Color(0xFFB9BEC7))
                : null,
            onTap: () => _editStep(i),
          ),
        if (sees.isNotEmpty)
          _row(
            leading: const Icon(Icons.visibility_outlined,
                size: 18, color: Glass.inkSoft),
            title: 'Sees $sees',
            maxLines: 3,
          ),
      ],
    ]);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
      );

  Widget _card(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Glass.radiusCard),
          border: Border.all(color: Glass.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 52, color: Glass.hairline),
            rows[i],
          ],
        ]),
      );

  Widget _row({
    required Widget leading,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
    int maxLines = 1,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(children: [
          SizedBox(width: 24, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Glass.ink, fontSize: 15, height: 1.3)),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          if (trailing == null && onTap != null)
            const Icon(Icons.chevron_right, color: Color(0xFFB9BEC7)),
        ]),
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Glass.radiusCard),
          border: Border.all(color: Glass.hairline),
        ),
        child: Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Glass.ink)),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Glass.ink, fontSize: 15)),
        ]),
      );
}
