import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge.dart';
import 'glyf_api.dart';
import 'telemetry.dart';
import 'theme.dart';

/// "What Glyf sends", asked once: Google Play's prominent disclosure. A
/// keyboard that sends the sentence you are typing, or your saved details,
/// has to say so in the app, outside settings, and get a yes before it does.
///
/// Agree turns on AI suggestions as you type (`aiSuggest`: on a pause, the
/// sentence before the cursor goes to the server so the strip can offer an
/// action) and lets AI requests carry saved details (`aiUsesVault`). Not now
/// leaves both off, and AI runs only when the person starts it. `aiConsent`
/// records when they answered; until then the keyboards send neither (iOS
/// `askForSuggestion` and `BackendClient.shareableProfile`, Android
/// `GlyfIME.scheduleSuggestion` and `shareableProfile`).
class AiConsent {
  static Future<bool> needed() async =>
      (await GlyfBridge.sharedSettings())['aiConsent'] == null;

  static Future<void> answer(bool agreed) async {
    await GlyfBridge.updateSharedSettings((s) => s
      ..['aiSuggest'] = agreed
      ..['aiUsesVault'] = agreed
      ..['aiConsent'] = DateTime.now().toUtc().toIso8601String());
    unawaited(Telemetry.log('ai_consent', {'agreed': agreed}));
  }
}

/// The words, in four rows that can be read at a glance (Arpit, 2026-10-06:
/// the screen "doesnt look good"), saying all the same things: what stays on
/// the phone, what goes and when, the saved details, and what never goes.
class AiConsentText extends StatelessWidget {
  const AiConsentText({super.key});

  static const _soft = TextStyle(color: Glass.inkSoft, fontSize: 13, height: 1.4);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _ConsentRow(
        icon: Icons.lock_outline_rounded,
        tint: Glass.success,
        title: 'Stays on your phone',
        body: 'What you type, autocorrect and the words Glyf learns.',
      ),
      const _ConsentRow(
        icon: Icons.auto_awesome_rounded,
        tint: Glass.accent,
        title: 'Goes to Glyf’s server and an AI provider',
        body: 'Only when you use AI: hold space, Rewrite, Translate, Ask Glyf or one of your glyfs. '
            'With AI suggestions on, also the sentence you pause on, so the strip can offer an action.',
      ),
      const _ConsentRow(
        icon: Icons.badge_outlined,
        tint: Color(0xFF0A84FF),
        title: 'Your saved details, when they help',
        body: 'With your details on, AI requests also carry what you saved (name, email, phone, '
            'address, links) so answers can fill them in.',
      ),
      const _ConsentRow(
        icon: Icons.shield_outlined,
        tint: Color(0xFFFF9F0A),
        title: 'Never',
        body: 'Nothing from password fields. Card numbers, codes and keys are masked first. '
            'AI providers don’t keep it or train on it. No ads, and your data is never sold.',
      ),
      const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('Searches go to Glyf’s search providers, GIF searches to KLIPY.', style: _soft),
      ),
      Semantics(
        identifier: 'consent:privacy',
        button: true,
        child: TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          onPressed: () => GlyfBridge.openURL(privacyPolicyURL),
          child: const Text('Privacy policy',
              style: TextStyle(color: Glass.accent, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.icon, required this.tint, required this.title, required this.body});

  final IconData icon;
  final Color tint;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, height: 1.4)),
            ]),
          ),
        ]),
      );
}

/// Asked once: on Turn on Glyf's first Open or Choose (before the keyboard
/// can send anything), or on opening the app for anyone who hasn't answered.
/// A choice is the only way out; closing it is not a yes.
Future<void> showAiConsentSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Glass.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (ctx) {
      Future<void> pick(bool agreed) async {
        await AiConsent.answer(agreed);
        if (ctx.mounted) Navigator.of(ctx).pop();
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('What Glyf sends',
                  style: TextStyle(color: Glass.ink, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              const Flexible(child: SingleChildScrollView(child: AiConsentText())),
              const SizedBox(height: 12),
              Semantics(
                identifier: 'consent:agree',
                button: true,
                child: PillButton(label: 'Agree and turn on', onPressed: () => pick(true)),
              ),
              Semantics(
                identifier: 'consent:notnow',
                button: true,
                child: TextButton(
                  onPressed: () => pick(false),
                  child: const Text('Not now',
                      style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
                ),
              ),
            ]),
          ),
        ),
      );
    },
  );
}
