import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../profile/brand_marks.dart' show PhantomMark;
import 'solana.dart';
import 'wallet_api.dart';
import 'pay_status_screen.dart';
import 'wallet_flow.dart';

/// Send SOL or USDC to an address, or USDC privately through MagicBlock.
/// Opened from Profile → Wallet, or from the keyboard with the address it
/// saw (and an amount, when the message had one).
class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.to, this.amount, this.token});

  final String? to;
  final String? amount;

  /// "USDC" or "SOL".
  final String? token;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  late final _to = TextEditingController(text: widget.to ?? '');
  late final _amount = TextEditingController(text: widget.amount ?? '');
  late TokenInfo _token = widget.token?.toUpperCase() == 'SOL' ? TokenInfo.sol : TokenInfo.usdc;
  bool _private = false;
  /// Glyf's fee on a private send, in basis points (0 when there is none).
  int _feeBps = 0;
  bool _busy = false;
  String? _error;
  BigInt? _balance;

  @override
  void initState() {
    super.initState();
    _to.addListener(() => setState(() => _error = null));
    _amount.addListener(() => setState(() => _error = null));
    WalletFlow.link.addListener(_loadBalance);
    WalletFlow.load().then((_) => _loadBalance());
    PrivateFee.config().then((f) {
      if (mounted) setState(() => _feeBps = f.bps);
    });
  }

  @override
  void dispose() {
    WalletFlow.link.removeListener(_loadBalance);
    _to.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final link = WalletFlow.link.value;
    if (link == null) return;
    try {
      final balance = _token.mint == Sol.wsol
          ? await SolanaRpc.solBalance(link.address)
          : await SolanaRpc.tokenBalance(link.address, _token.mint);
      if (mounted) setState(() => _balance = balance);
    } on WalletError {
      // The balance is a nicety; sending still works without it.
    }
  }

  void _pick(TokenInfo token) {
    setState(() {
      _token = token;
      _balance = null;
      if (token.mint == Sol.wsol) _private = false;
    });
    _loadBalance();
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text != null && text.isNotEmpty) _to.text = text;
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final start = await WalletFlow.send(to: _to.text, amount: _amount.text, token: _token, private: _private);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = start.error;
    });
    final progress = start.progress;
    if (progress != null) {
      // Signed on this phone: the status screen rides along from here.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PayStatusScreen(progress: progress)),
      );
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final error = await WalletFlow.connect();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Send', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ValueListenableBuilder<WalletLink?>(
        valueListenable: WalletFlow.link,
        builder: (context, link, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (link == null) ...[_connectFirst(), const SizedBox(height: 16)],
            _label('To'),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'send:to',
                      child: TextField(
                        controller: _to,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLines: 2,
                        minLines: 1,
                        // Inter draws "2x6" as "2×6"; never in an address.
                        style: const TextStyle(
                          color: Glass.ink,
                          fontSize: 15,
                          fontFeatures: [FontFeature.disable('calt')],
                        ),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: 'Solana address'),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste_rounded, size: 20, color: Glass.inkSoft),
                    onPressed: _paste,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _label('Amount'),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'send:amount',
                      child: TextField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                          color: Glass.ink,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: '0'),
                      ),
                    ),
                  ),
                  _tokenPicker(),
                ],
              ),
            ),
            if (_balance != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  'You have ${Sol.format(_balance!, _token.decimals, maxDecimals: _token.mint == Sol.wsol ? 4 : 2)} ${_token.symbol}',
                  style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5),
                ),
              ),
            if (_token.mint == Sol.usdc) ...[
              const SizedBox(height: 18),
              GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Send privately',
                            style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _feeBps > 0
                                ? 'Through MagicBlock, so it isn’t linked to you on chain. About 0.002 SOL + 0.1%, and Glyf’s ${PrivateFee.percent(_feeBps)}%.'
                                : 'Through MagicBlock, so it isn’t linked to you on chain. About 0.002 SOL + 0.1%.',
                            style: TextStyle(color: Glass.inkSoft, fontSize: 13, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Semantics(
                      identifier: 'send:private',
                      toggled: _private,
                      child: CupertinoSwitch(
                        value: _private,
                        activeTrackColor: Glass.ink,
                        onChanged: (v) => setState(() => _private = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Semantics(
              identifier: 'send:go',
              button: true,
              child: _busy
                  ? const SizedBox(
                      height: 52,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink),
                        ),
                      ),
                    )
                  : PillButton(label: link?.internal ?? false ? 'Send' : 'Review in Phantom', onPressed: link == null ? null : _send),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                identifier: 'send:error',
                liveRegion: true,
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Glass.danger, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _connectFirst() => GlassCard(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        const PhantomMark(size: 38),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Connect Phantom to send',
            style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _connect,
          child: const Text(
            'Connect',
            style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  Widget _tokenPicker() {
    Widget option(TokenInfo token) {
      final on = _token.mint == token.mint;
      return GestureDetector(
        onTap: () => _pick(token),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? Glass.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            token.symbol,
            style: TextStyle(color: on ? Colors.white : Glass.inkSoft, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Glass.bg, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [option(TokenInfo.usdc), option(TokenInfo.sol)]),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w600),
    ),
  );
}
