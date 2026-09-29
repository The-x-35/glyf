import 'package:flutter/material.dart';

import 'theme.dart';

/// A bottom sheet with one text field and one button. The text comes back
/// when the button is tapped, null when the sheet is dismissed.
///
/// The sheet owns the field's controller. A controller the caller disposed
/// as soon as the sheet's future completed was still in use while the sheet
/// slid away and the keyboard dropped, and that crashed the app.
///
/// [footer] is the last thing on the sheet, under the button: a quiet action
/// that belongs with the text but shouldn't be on the page (Profile's Edit
/// puts Delete account there). It gets the sheet's own context, to close it.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  int? maxLength,
  int maxLines = 1,
  bool autofocus = true,
  TextStyle style = const TextStyle(color: Glass.ink, fontSize: 16),
  Widget Function(BuildContext sheet)? footer,
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
      footer: footer,
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
    required this.footer,
  });

  final String title;
  final String action;
  final String initial;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;
  final TextStyle style;
  final Widget Function(BuildContext sheet)? footer;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _text = TextEditingController(text: widget.initial);

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
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: const Color(0xFFF7F8FA),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        PillButton(label: widget.action, onPressed: () => Navigator.of(context).pop(_text.text)),
        const SizedBox(height: 4),
        if (widget.footer != null) widget.footer!(context),
      ]),
    );
  }
}
