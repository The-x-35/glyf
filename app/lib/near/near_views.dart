import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme.dart';
import 'near_api.dart';
import 'near_flow.dart';

/// A NEAR Intents quote on the trade screen: what goes out and on which
/// chain, what arrives where and for whom, how long it takes, and anything
/// Guard said about the recipient.
class NearQuoteCard extends StatelessWidget {
  const NearQuoteCard({super.key, required this.quote, this.recipient});

  final NearQuote quote;
  final String? recipient;

  @override
  Widget build(BuildContext context) {
    final secs = quote.timeSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            Semantics(
              identifier: 'trade:near:pay',
              child: _side('You pay', quote.amountIn, quote.sell, quote.amountInUsd),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16, color: Glass.hairline),
            Semantics(
              identifier: 'trade:near:get',
              child: _side('You get', quote.amountOut, quote.buy, quote.amountOutUsd,
                  approx: true, to: recipient),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text(
          '${secs == null ? '' : '~$secs s · '}via ${NearFlow.venue}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        for (final c in quote.checks) ...[
          const SizedBox(height: 8),
          Semantics(
            identifier: 'trade:near:check:${c.id}',
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(c.level == 'block' ? Icons.gpp_bad_rounded : Icons.warning_amber_rounded,
                  size: 18, color: c.level == 'block' ? Glass.danger : Glass.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.text,
                  style: TextStyle(
                    color: c.level == 'block' ? Glass.danger : Glass.warning,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _side(String label, String amount, NearAsset asset, String? usd, {bool approx = false, String? to}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                '${approx ? '≈ ' : ''}${_amount(amount)} ${asset.symbol}',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(
                  color: Glass.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.disable('calt')],
                ),
              ),
              if (to != null)
                Text('to $to', style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _chainPill(NearFlow.chainLabel(asset.chain)),
            if (usd != null) ...[
              const SizedBox(height: 6),
              Text('\$${_amount(usd, places: 2)}', style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5)),
            ],
          ]),
        ]),
      );

  Widget _chainPill(String chain) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Glass.bg, borderRadius: BorderRadius.circular(12)),
        child: Text(chain, style: const TextStyle(color: Glass.ink, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  static String _amount(String v, {int? places}) {
    final d = double.tryParse(v);
    if (d == null) return v;
    var s = d.toStringAsFixed(places ?? (d >= 1000 ? 2 : d >= 1 ? 4 : 6));
    if (places == null) {
      while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
        s = s.substring(0, s.length - 1);
      }
    }
    return s;
  }
}

/// The deposit for a chain Glyf can't sign on: a QR code of the address,
/// and the amount, address and memo to copy into any wallet.
class NearDepositCard extends StatelessWidget {
  const NearDepositCard({super.key, required this.quote});

  final NearQuote quote;

  @override
  Widget build(BuildContext context) {
    final address = quote.depositAddress ?? '';
    return GlassCard(
      child: Column(children: [
        Semantics(
          identifier: 'trade:near:qr',
          child: QrImageView(data: address, size: 176, padding: EdgeInsets.zero, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 14),
        _CopyRow(id: 'amount', label: 'Amount', value: '${quote.amountIn} ${quote.sell.symbol}', copy: quote.amountIn),
        const Divider(height: 1, color: Glass.hairline),
        _CopyRow(id: 'address', label: 'Address', value: address),
        if (quote.depositMemo != null && quote.depositMemo!.isNotEmpty) ...[
          const Divider(height: 1, color: Glass.hairline),
          _CopyRow(id: 'memo', label: 'Memo', value: quote.depositMemo!),
        ],
      ]),
    );
  }
}

/// One thing to copy. The icon turns to a tick for a moment; no toast.
class _CopyRow extends StatefulWidget {
  const _CopyRow({required this.id, required this.label, required this.value, this.copy});

  final String id;
  final String label;
  final String value;

  /// What goes on the clipboard, when it isn't [value] as shown.
  final String? copy;

  @override
  State<_CopyRow> createState() => _CopyRowState();
}

class _CopyRowState extends State<_CopyRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.copy ?? widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        identifier: 'trade:near:copy:${widget.id}',
        button: true,
        child: InkWell(
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              SizedBox(
                width: 70,
                child: Text(widget.label,
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Text(
                  widget.value,
                  style: const TextStyle(
                    color: Glass.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    fontFeatures: [FontFeature.disable('calt')],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18, color: Glass.ink),
            ]),
          ),
        ),
      );
}
