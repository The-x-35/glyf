import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:privy_flutter/privy_flutter.dart';

import '../core/dismiss_keyboard.dart';
import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// The wallet, where a wallet belongs: in the app, never in the keyboard.
///
/// Keys live in Privy's embedded Solana wallet, which the person unlocks with
/// their own email — Glyf never sees a private key and the server never holds
/// one either. A payment is built by the server through MagicBlock's private
/// payments API (sender, amount and recipient are not linked on chain), comes
/// back as an unsigned transaction, and is signed and sent here.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.prefillTo, this.prefillAmount});

  /// Handed over by the keyboard when a chat asked for a payment.
  final String? prefillTo;
  final String? prefillAmount;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Privy? _privy;
  PrivyUser? _user;
  EmbeddedSolanaWallet? _wallet;

  bool _loading = true;
  String? _setupNeeded;
  String? _error;
  String? _status;
  bool _codeSent = false;
  bool _busy = false;

  final _email = TextEditingController();
  final _code = TextEditingController();
  late final TextEditingController _to =
      TextEditingController(text: widget.prefillTo ?? '');
  late final TextEditingController _amount =
      TextEditingController(text: widget.prefillAmount ?? '');

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _to.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final cfg = await GlyfApi.walletConfig();
    if (!mounted) return;
    if (cfg == null) {
      setState(() {
        _loading = false;
        _error = 'Cannot reach the Glyf server.';
      });
      return;
    }
    if (cfg['ok'] == false) {
      // The server answered but turned us away (a session that lapsed, a
      // rate limit): that is not "payments are off", so say what it is.
      setState(() {
        _loading = false;
        _error = (cfg['error'] as String?) ?? 'Cannot reach the Glyf server.';
      });
      return;
    }
    if (cfg['ready'] != true) {
      setState(() {
        _loading = false;
        _setupNeeded = 'Private payments are not switched on for this Glyf server yet.';
      });
      return;
    }
    final privy = Privy.init(
      config: PrivyConfig(
        appId: cfg['privyAppId'] as String,
        appClientId: cfg['privyAppClientId'] as String,
        logLevel: PrivyLogLevel.error,
      ),
    );
    final state = await privy.getAuthState();
    if (!mounted) return;
    setState(() {
      _privy = privy;
      _loading = false;
    });
    if (state is Authenticated) {
      await _adopt(state.user);
    }
  }

  /// Takes the signed-in user and makes sure there is a Solana wallet.
  Future<void> _adopt(PrivyUser user) async {
    var wallet = user.embeddedSolanaWallets.firstOrNull;
    if (wallet == null) {
      final made = await user.createSolanaWallet();
      made.fold(
        onSuccess: (w) => wallet = w,
        onFailure: (e) => setState(() => _error = e.message),
      );
    }
    if (!mounted) return;
    setState(() {
      _user = user;
      _wallet = wallet;
      _status = null;
    });
    Telemetry.log('wallet_ready', {'hasWallet': wallet != null});
  }

  Future<void> _sendCode() async {
    final privy = _privy;
    if (privy == null) return;
    setState(() { _busy = true; _error = null; });
    final res = await privy.email.sendCode(_email.text.trim());
    if (!mounted) return;
    res.fold(
      onSuccess: (_) => setState(() { _codeSent = true; _busy = false; }),
      onFailure: (e) => setState(() { _error = e.message; _busy = false; }),
    );
  }

  Future<void> _verify() async {
    final privy = _privy;
    if (privy == null) return;
    setState(() { _busy = true; _error = null; });
    final res = await privy.email.loginWithCode(
      code: _code.text.trim(), email: _email.text.trim());
    if (!mounted) return;
    res.fold(
      onSuccess: (user) {
        _adopt(user).then((_) {
          if (mounted) setState(() => _busy = false);
        });
      },
      onFailure: (e) => setState(() { _error = e.message; _busy = false; }),
    );
  }

  /// Build with MagicBlock, sign with Privy, send to Solana.
  Future<void> _send() async {
    final wallet = _wallet;
    if (wallet == null) return;
    final to = _to.text.trim();
    final amount = _amount.text.trim();
    if (to.length < 32 || amount.isEmpty) {
      setState(() => _error = 'Need an address and an amount.');
      return;
    }
    setState(() { _busy = true; _error = null; _status = 'Building a private transfer…'; });
    final built = await GlyfApi.buildTransfer(
      from: wallet.address, to: to, amount: amount);
    if (!mounted) return;
    if (built == null || built['ok'] != true) {
      setState(() {
        _busy = false;
        _status = null;
        _error = (built?['error'] as String?) ?? 'Could not build that payment.';
      });
      return;
    }
    setState(() => _status = 'Waiting for you to approve it…');
    final bytes = base64Decode(built['transactionBase64'] as String);
    final res = await wallet.provider.signAndSendTransaction(
      transaction: Uint8List.fromList(bytes));
    if (!mounted) return;
    res.fold(
      onSuccess: (signature) {
        Telemetry.log('wallet_sent', {'private': true});
        setState(() {
          _busy = false;
          _status = 'Sent privately · $signature';
        });
        // The keyboard is waiting for a line to type back into the chat.
        GlyfBridge.writeAppPong('sent $amount USDC privately');
      },
      onFailure: (e) => setState(() {
        _busy = false;
        _status = null;
        _error = e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboard(child: Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Wallet',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
          children: [
            if (_loading) const Center(child: Padding(
              padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
            if (_setupNeeded != null) _card(children: [
              const Text('Not set up yet',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_setupNeeded!,
                  style: const TextStyle(fontSize: 14, color: Glass.inkSoft)),
            ]),
            if (!_loading && _setupNeeded == null && _user == null) _login(),
            if (_wallet != null) ..._walletBody(),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 13, color: Glass.danger)),
            ),
            if (_status != null) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_status!,
                  style: const TextStyle(fontSize: 13, color: Glass.inkSoft)),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Glass.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _field(TextEditingController c, String hint,
          {TextInputType? type}) =>
      TextField(
        controller: c,
        keyboardType: type,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(color: Glass.inkSoft),
          border: InputBorder.none,
        ),
      );

  Widget _login() => _card(children: [
        const Text('Sign in to your wallet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _field(_email, 'you@example.com', type: TextInputType.emailAddress),
        if (_codeSent) ...[
          const Divider(height: 22),
          _field(_code, '6-digit code', type: TextInputType.number),
        ],
        const SizedBox(height: 14),
        _pill(_codeSent ? 'Verify' : 'Send code',
            onTap: _busy ? null : (_codeSent ? _verify : _sendCode)),
      ]);

  List<Widget> _walletBody() => [
        _card(children: [
          const Text('Your Solana wallet',
              style: TextStyle(fontSize: 13, color: Glass.inkSoft)),
          const SizedBox(height: 4),
          SelectableText(_wallet!.address,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        _card(children: [
          const Text('Send USDC privately',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _field(_to, 'Recipient address'),
          const Divider(height: 22),
          _field(_amount, 'Amount in USDC',
              type: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 14),
          _pill(_busy ? 'Working…' : 'Send privately',
              onTap: _busy ? null : _send),
        ]),
      ];

  Widget _pill(String label, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null ? Glass.inkSoft : Glass.pill,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      );
}
