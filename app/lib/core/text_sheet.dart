import 'package:flutter/material.dart';

import 'theme.dart';

/// A bottom sheet with one text field and one button. The text comes back
/// when the button is tapped, null when the sheet is dismissed. With
/// [check], text it answers a reason for stays in the sheet with that
/// reason under the field.
///
/// The sheet owns the field's controller. A controller the caller disposed
/// as soon as the sheet's future completed was still in use while the sheet
/// slid away and the keyboard dropped, and that crashed the app.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  int? maxLength,
  int maxLines = 1,
  bool autofocus = true,
  TextStyle style = const TextStyle(color: Glass.ink, fontSize: 16),
  String? Function(String text)? check,
  TextCapitalization capitalization = TextCapitalization.none,
  bool autocorrect = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (_) => _TextSheet(
      title: title,
      action: action,
      initial: initial,
      maxLength: maxLength,
      maxLines: maxLines,
      autofocus: autofocus,
      style: style,
      check: check,
      capitalization: capitalization,
      autocorrect: autocorrect,
    ),
  );
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({
    required this.title,
    required this.action,
    required this.initial,
    required this.maxLength,
    required this.maxLines,
    required this.autofocus,
    required this.style,
    this.check,
    this.capitalization = TextCapitalization.none,
    this.autocorrect = true,
  });

  final String title;
  final String action;
  final String initial;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;
  final TextStyle style;
  final String? Function(String text)? check;
  final TextCapitalization capitalization;
  final bool autocorrect;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;

  void _done() {
    final error = widget.check?.call(_text.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_text.text);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 22, right: 22, top: 18, bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.title,
            style: const TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: widget.autofocus,
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          style: widget.style,
          textCapitalization: widget.capitalization,
          autocorrect: widget.autocorrect,
          enableSuggestions: widget.autocorrect,
          onChanged: _error == null ? null : (_) => setState(() => _error = null),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: const Color(0xFFF7F8FA),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Glass.danger, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 12),
        PillButton(label: widget.action, onPressed: _done),
        const SizedBox(height: 4),
      ]),
    );
  }
}
