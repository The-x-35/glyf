import 'dart:ui' show Color;

/// The website's chats (site/components/chat/scenarios.ts), word for word,
/// played on the real keyboard. Each chat is a small level: a friend asks
/// for something, you get it done on the keyboard, and the keyboard rings
/// the one thing to tap. Anything that needs typing is typed for you.
///
/// Where the website checks for its own canned answer (a fixed sunset time,
/// a fixed rewrite), the check here accepts what the real keyboard produces.

class TourVault {
  const TourVault({this.address, this.wallet, this.addresses = const []});
  final String? address;
  /// The Solana wallet address, for "what's your wallet address?".
  final String? wallet;
  /// Every saved address: whichever one is sent answers "what's your address?".
  final List<String> addresses;
}

class TourBeat {
  const TourBeat({
    required this.them,
    required this.goal,
    required this.reply,
    required this.nudge,
    this.prefill,
    this.autotype,
    this.tapback,
    this.payAmount,
    this.otherLanguage,
  });

  final List<String> them;

  /// Typed into the box as soon as the friend has asked.
  final String? prefill;

  /// What the keyboard types for you next, given the text so far.
  final String? Function(String text)? autotype;

  final bool Function(String sent, TourVault vault) goal;
  final List<String> Function(String sent) reply;
  final String? tapback;
  final String nudge;

  /// A payment this beat asks for (the practice wallet shows it).
  final String? payAmount;

  /// The language the other person writes in, for translate.
  final String? otherLanguage;
}

class TourScenario {
  const TourScenario({
    required this.id,
    required this.name,
    required this.avatar,
    required this.tint,
    required this.tag,
    required this.headline,
    required this.beats,
  });

  final String id;
  final String name;
  final String avatar;
  final Color tint;
  final String tag;
  final (String, String) headline;
  final List<TourBeat> beats;

  /// What the chat shows before it's opened: the ask, not a pasted address.
  String get teaser {
    final lines = beats.first.them;
    return lines.reversed.firstWhere((l) => !isSolAddress(l), orElse: () => lines.last);
  }
}

const semiWallet = '8QvS3nE5d1YwZk7pLr2mXh9TbF4cJaGuVy6oKe1RtNqP';

bool isSolAddress(String s) =>
    RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(s.trim());

bool _has(String s, String part) => s.toLowerCase().contains(part.toLowerCase());

/// The place's name out of what the keyboard sends for a place.
String placeName(String sent) {
  final line = sent.split('\n').firstWhere((l) => l.contains('📍'), orElse: () => sent);
  return line.replaceFirst(RegExp(r'^.*📍\s*'), '').split(' · ').first.trim();
}

final tourScenarios = <TourScenario>[
  TourScenario(
    id: 'sakshi',
    name: 'Sakshi',
    avatar: '☕',
    tint: const Color(0xFF30B0C7),
    tag: 'Maps',
    headline: ('Where to meet?', 'Maps, mid-chat.'),
    beats: [
      TourBeat(
        them: ['free this evening? 😊', "let's get coffee ☕ where should we meet?"],
        goal: (t, _) => t.contains('📍'),
        reply: (sent) => ['perfect 🙌 ${placeName(sent)} at 6 then', "can't wait to catch up!"],
        tapback: '❤️',
        nudge: 'send me a place 😄',
      ),
    ],
  ),
  TourScenario(
    id: 'mom',
    name: 'Mom',
    avatar: '🎁',
    tint: const Color(0xFFFF6FAE),
    tag: 'Vault',
    headline: ('Never type your', 'address again.'),
    beats: [
      TourBeat(
        them: ['hi sweetie 🎉', 'sending you something for your birthday', "what's your address?"],
        goal: (t, v) => v.addresses.isNotEmpty
            ? v.addresses.any((a) => _has(t, a))
            : RegExp(r'\d').hasMatch(t) && t.trim().length > 12,
        reply: (_) => ['got it ❤️', "it'll be there by friday"],
        tapback: '❤️',
        nudge: "honey, what's your address? 🙈",
      ),
    ],
  ),
  TourScenario(
    id: 'semi',
    name: 'Semi',
    avatar: '🏆',
    tint: const Color(0xFFBF5AF2),
    tag: 'Private pay + swaps',
    headline: ('Pay on Solana.', 'Privately.'),
    beats: [
      TourBeat(
        them: ['the server bill just hit 😩', 'can you send \$200 for server costs? usdc on sol', semiWallet],
        payAmount: '200',
        goal: (t, _) => t.startsWith('💸'),
        reply: (_) => ['got it, thank you', 'and nobody onchain can see who paid lol 🥷'],
        tapback: '🙏',
        nudge: 'did it go through? 👀',
      ),
    ],
  ),
  TourScenario(
    id: 'neha',
    name: 'Neha',
    avatar: '💼',
    tint: const Color(0xFF5E5CE6),
    tag: 'AI rewrite',
    headline: ('Type it messy.', 'Send it polished.'),
    beats: [
      TourBeat(
        them: ['Hi! Could you send the Q3 deck to the client by EOD?'],
        prefill: 'ya ill send it by 6 dont worry',
        goal: (t, _) {
          final s = t.trim().toLowerCase();
          return s.isNotEmpty && s != 'ya ill send it by 6 dont worry' && !s.contains('dont worry');
        },
        reply: (_) => ['Perfect, thank you! 🙌'],
        tapback: '👍',
        nudge: 'Haha, maybe a little more formal? 😅',
      ),
    ],
  ),
  TourScenario(
    id: 'zoya',
    name: 'Zoya',
    avatar: '🍝',
    tint: const Color(0xFFFF375F),
    tag: 'Math + wallet',
    headline: ('Do the math.', 'Get paid.'),
    beats: [
      TourBeat(
        them: ['dinner was so good 😭', 'bill was \$236 for 4 of us. how much do I send you?'],
        autotype: (t) => t.isEmpty ? '236/4' : null,
        goal: (t, _) => t.contains('59'),
        reply: (_) => ['sending now 💸'],
        nudge: 'wait, how much though? 😅',
      ),
      TourBeat(
        them: ["what's your wallet address?"],
        autotype: (t) => t.isEmpty ? 'my wallet address is ' : null,
        goal: (t, v) => v.wallet != null ? _has(t, v.wallet!) : RegExp(r'[1-9A-HJ-NP-Za-km-z]{32,44}').hasMatch(t),
        reply: (_) => ['done ✅ 59 USDC sent'],
        tapback: '👍',
        nudge: 'your wallet address? 🙏',
      ),
    ],
  ),
  TourScenario(
    id: 'kabir',
    name: 'Kabir',
    avatar: '🚗',
    tint: const Color(0xFF34C759),
    tag: 'YouTube + Google',
    headline: ('Send the song,', 'not the search.'),
    beats: [
      TourBeat(
        them: ['road trip tomorrow 🚗', 'send me something good for the drive'],
        goal: (t, _) => t.contains('youtu') || t.contains('🎥'),
        reply: (_) => ['ok this slaps 🔥'],
        tapback: '🔥',
        nudge: 'send a song 😄',
      ),
      TourBeat(
        them: ['also, terrace at sunset today? 🌇', 'what time is sunset?'],
        goal: (t, _) => RegExp(r'\d{1,2}:\d{2}').hasMatch(t),
        reply: (_) => ['see you up there ☀️'],
        tapback: '❤️',
        nudge: 'what time though? 🌅',
      ),
    ],
  ),
  TourScenario(
    id: 'sofia',
    name: 'Sofía',
    avatar: '🌊',
    tint: const Color(0xFF0A84FF),
    tag: 'Translate',
    headline: ('Reply in Spanish.', 'No lessons.'),
    beats: [
      TourBeat(
        them: ['¡Hola! 👋', '¿Nos vemos mañana?'],
        otherLanguage: 'Spanish',
        goal: (t, _) => _has(t, 'mañana'),
        reply: (_) => ['¡Perfecto! Hasta mañana 🌊'],
        tapback: '❤️',
        nudge: '¿Cómo? 😅',
      ),
    ],
  ),
];

/// Times shown on chats before they're opened.
const earlierTimes = ['9:41 AM', '9:38 AM', '9:30 AM', '9:12 AM', '8:55 AM', '8:20 AM', 'Yesterday', 'Yesterday'];
