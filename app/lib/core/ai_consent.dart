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

/// The words, shared by the onboarding step and the sheet existing users see.
class AiConsentText extends StatelessWidget {
  const AiConsentText({super.key});

  static const _body = TextStyle(color: Glass.ink, fontSize: 15, height: 1.4);
  static const _soft = TextStyle(color: Glass.inkSoft, fontSize: 13.5, height: 1.4);

  Widget _point(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  ', style: _body),
          Expanded(child: Text(text, style: _body)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
          'Glyf is a keyboard, so it sees what you type. Typing, autocorrect '
          'and the words it learns stay on this phone.',
          style: _body),
      const SizedBox(height: 14),
      const Text('Text goes to Glyf’s server, and from there to an AI provider, only:',
          style: _body),
      _point('when you use AI: hold space, Rewrite, Translate, Ask Glyf or one of your glyfs'),
      _point('with AI suggestions on: the sentence you’re typing when you pause, '
          'so the strip can offer an action'),
      const SizedBox(height: 14),
      const Text(
          'With your details on, AI requests also carry what you saved (name, '
          'email, phone, address, links) so answers can fill them in.',
          style: _body),
      const SizedBox(height: 14),
      const Text(
          'Nothing is sent from password fields. Card numbers, codes and keys '
          'are masked first, and AI providers don’t keep it or train on it. '
          'Searches go to Glyf’s search providers, GIF searches to KLIPY. '
          'No ads, and your data is never sold.',
          style: _soft),
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

/// For someone who set Glyf up before this was asked: once, on opening the
/// app. A choice is the only way out; closing it is not a yes.
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
