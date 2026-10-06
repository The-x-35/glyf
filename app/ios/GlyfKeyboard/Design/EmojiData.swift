import Foundation

/// The emoji board's data: every emoji on Apple's keyboard (iOS 26.5), in its
/// eight tabs and its order (Arpit, 2026-10-03: "make sure we are not missing
/// any emoji compared to apple"), with Unicode's name and Emoji version for
/// each, CLDR's English keywords for search, and its skin tones. One table for
/// both keyboards (shared/emoji/emoji.tsv, from tools/emoji/build.py; Android
/// reads it from its assets). An emoji this iOS can't draw yet is left out by
/// its Emoji version, so no empty boxes.
enum EmojiData {

    struct Emoji {
        let emoji: String
        let version: String
        let name: String
        let keywords: [String]
        /// Skin-tone variants with their own Emoji versions.
        let tones: [(emoji: String, version: String)]
    }

    /// The iOS release that first drew each Emoji version. Glyf needs iOS 17,
    /// which draws everything up to 15.0.
    private static let firstIOS: [String: (Int, Int)] = [
        "15.1": (17, 4), "16.0": (18, 4), "17.0": (26, 4),
    ]

    /// Whether this iOS draws an emoji of this Emoji version. One newer than
    /// the table is left out until the table knows it.
    static func drawable(_ version: String,
                         os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        if let (major, minor) = firstIOS[version] {
            return (os.majorVersion, os.minorVersion) >= (major, minor)
        }
        return (Double(version) ?? 99) <= 15.0
    }

    private struct Loaded {
        var tabs: [(id: String, emoji: [Emoji])] = []
        var byEmoji: [String: Emoji] = [:]
        /// A toned emoji's own ("👍🏽" → "👍").
        var toneBase: [String: String] = [:]
        var seed: [String] = []
    }

    /// The table, read once, with what this phone can draw.
    private static let loaded: Loaded = {
        var out = Loaded()
        var order: [String] = []
        var byTab: [String: [Emoji]] = [:]
        for line in table.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# seed: ") {
                out.seed = line.dropFirst("# seed: ".count).split(separator: " ").map(String.init)
                continue
            }
            if line.hasPrefix("#") { continue }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 7, drawable(f[2]) else { continue }
            let variants = f[5].isEmpty ? [] : f[5].split(separator: ",").map(String.init)
            let versions = f[6].split(separator: ",").map(String.init)
            let tones = variants.enumerated().map { i, v in
                (emoji: v, version: versions.count == variants.count ? versions[i] : (versions.first ?? f[2]))
            }.filter { drawable($0.version) }
            let e = Emoji(emoji: f[1], version: f[2], name: f[3],
                          keywords: f[4].isEmpty ? [] : f[4].split(separator: "|").map(String.init), tones: tones)
            if byTab[f[0]] == nil { order.append(f[0]) }
            byTab[f[0], default: []].append(e)
            out.byEmoji[f[1]] = e
            for t in tones { out.toneBase[t.emoji] = f[1] }
        }
        out.tabs = order.map { ($0, byTab[$0] ?? []) }
        return out
    }()

    private static let symbols: [String: String] = [
        "smileys": "face.smiling", "animals": "teddybear", "food": "takeoutbag.and.cup.and.straw",
        "activity": "soccerball", "travel": "car", "objects": "lightbulb", "symbols": "heart", "flags": "flag",
    ]

    /// Apple's eight tabs after Frequently Used: the tab, its glyph, its emoji.
    static let categories: [(id: String, symbol: String, emoji: [String])] =
        loaded.tabs.map { ($0.id, symbols[$0.id] ?? "face.smiling", $0.emoji.map(\.emoji)) }

    /// Frequently Used before anything has been used: the world's most used
    /// emoji (Unicode's 2021 ranking).
    static var seed: [String] { loaded.seed.filter { loaded.byEmoji[$0] != nil } }

    static func info(_ emoji: String) -> Emoji? { loaded.byEmoji[emoji] }

    static let skinTones = ["🏻", "🏼", "🏽", "🏾", "🏿"]

    /// The emoji and its five tones, as a long press shows them. Two-person
    /// emoji have 25 (a tone each); the five where both match are shown.
    static func variants(of base: String) -> [String] {
        guard let e = loaded.byEmoji[base], !e.tones.isEmpty else { return [base] }
        let one = e.tones.map(\.emoji).filter { v in
            Set(v.unicodeScalars.filter { (0x1F3FB...0x1F3FF).contains($0.value) }.map(\.value)).count == 1
        }
        return [base] + one.prefix(5)
    }

    /// The emoji a toned one belongs to ("👍🏽" → "👍").
    static func base(of emoji: String) -> String { loaded.toneBase[emoji] ?? emoji }

    /// Names people use that Unicode's don't say (a country's short name).
    private static let aliases: [(String, String)] = [
        ("usa", "🇺🇸"), ("us", "🇺🇸"), ("america", "🇺🇸"), ("uk", "🇬🇧"), ("britain", "🇬🇧"), ("england", "🏴󠁧󠁢󠁥󠁮󠁧󠁿"),
        ("uae", "🇦🇪"), ("lol", "😂"), ("rofl", "🤣"), ("lmao", "😂"), ("ty", "🙏"), ("thanks", "🙏"), ("omg", "😱"),
        ("xd", "😆"), ("dino", "🦖"), ("boba", "🧋"), ("hotdog", "🌭"), ("ok", "👌"), ("haha", "😂"),
    ]

    /// Search by name and keyword, best first: the name itself, a name that
    /// ends with it ("red heart" for "heart"), one that starts with it, every
    /// word starting a word of the name, then of a keyword ("tears" → 🥹 😂
    /// 😭 …). The most used emoji (the seed) break ties, then board order.
    static func search(_ query: String, limit: Int = 24) -> [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: " ").map(String.init)
        func split(_ s: String) -> [Substring] {
            s.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
        }
        let popular = Dictionary(loaded.seed.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var scored: [(score: Int, index: Int, emoji: String)] = []
        var index = 0
        for tab in loaded.tabs {
            for e in tab.emoji {
                defer { index += 1 }
                let name = e.name.lowercased()
                let nameWords = split(name)
                let keyWords = e.keywords.flatMap { split($0) }
                func starts(_ pool: [Substring]) -> Bool {
                    words.allSatisfy { w in pool.contains { $0.hasPrefix(w) } }
                }
                var score = 0
                if name == q || name.hasSuffix(": " + q) { score = 100 }
                else if name.hasSuffix(" " + q) { score = 85 }
                else if name.hasPrefix(q) { score = 80 }
                else if starts(nameWords) { score = 60 }
                else if starts(nameWords + keyWords) { score = 40 }
                else if name.contains(q) { score = 20 }
                if score > 0 { scored.append((score, index, e.emoji)) }
            }
        }
        for (alias, emoji) in aliases where alias == q || (q.count >= 3 && alias.hasPrefix(q)) {
            scored.append((alias == q ? 90 : 50, -1, emoji))
        }
        var out: [String] = []
        func rank(_ e: String) -> Int { popular[e] ?? 999 }
        for s in scored.sorted(by: { ($0.score, -rank($0.emoji), -$0.index) > ($1.score, -rank($1.emoji), -$1.index) })
        where loaded.byEmoji[s.emoji] != nil && !out.contains(s.emoji) {
            out.append(s.emoji)
            if out.count >= limit { break }
        }
        return out
    }

    // GENERATED by tools/emoji/build.py: do not edit.
    static let table = #"""
# Glyf emoji board: every emoji on Apple's keyboard (iOS 26.5), in its tabs and order.
# tab, emoji, Emoji version, name, keywords, skin-tone variants, their versions (one, or one each).
# Built by tools/emoji/build.py from Unicode emoji-test.txt 17.0 and CLDR 48.2 annotations
# (Copyright Unicode, Inc., Unicode License v3: shared/emoji/LICENSE-UNICODE.txt).
# seed: 😂 ❤️ 🤣 👍 😭 🙏 😘 🥰 😍 😊 🎉 😁 💕 🥺 😅 🔥 ☺️ 🤦 ♥️ 🤷 🙄 😆 🤗 😉 🎂 🤔 👏 🙂 😳 🥳
smileys	😀	1.0	grinning face	cheerful|cheery|grin|happy|laugh|nice|smile|smiling|teeth		
smileys	😃	0.6	grinning face with big eyes	awesome|grin|happy|mouth|open|smile|smiling|teeth|yay		
smileys	😄	0.6	grinning face with smiling eyes	eye|grin|happy|laugh|lol|mouth|open|smile		
smileys	😁	0.6	beaming face with smiling eyes	eye|grin|grinning|happy|nice|smile|teeth		
smileys	😆	0.6	grinning squinting face	closed|eyes|haha|hahaha|happy|laugh|lol|mouth|open|rofl|smile|smiling		
smileys	🥹	14.0	face holding back tears	admiration|aww|cry|embarrassed|feelings|grateful|gratitude|joy|please|proud|resist|sad		
smileys	😅	0.6	grinning face with sweat	cold|dejected|excited|mouth|nervous|open|smile|smiling|stress|stressed		
smileys	😂	0.6	face with tears of joy	crying|feels|funny|haha|happy|hehe|hilarious|laugh|lmao|lol|rofl|roflmao|tear		
smileys	🤣	3.0	rolling on the floor laughing	crying|face|funny|haha|happy|hehe|hilarious|joy|laugh|lmao|lol|rofl|roflmao|tear		
smileys	🥲	13.0	smiling face with tear	glad|grateful|happy|joy|pain|proud|relieved|smile|smiley|touched		
smileys	☺️	0.6	smiling face	happy|outlined|relaxed|smile		
smileys	😊	0.6	smiling face with smiling eyes	blush|eye|glad|satisfied|smile		
smileys	😇	1.0	smiling face with halo	angel|angelic|angels|blessed|fairy|fairytale|fantasy|happy|innocent|peaceful|smile|spirit|tale		
smileys	🙂	1.0	slightly smiling face	happy|smile		
smileys	🙃	1.0	upside-down face	hehe|smile		
smileys	😉	0.6	winking face	flirt|heartbreaker|sexy|slide|tease|wink|winks		
smileys	😌	0.6	relieved face	calm|peace|relief|zen		
smileys	😍	0.6	smiling face with heart-eyes	143|bae|eye|feels|hearts|ily|kisses|love|romance|romantic|smile|xoxo		
smileys	🥰	11.0	smiling face with hearts	3|adore|crush|heart|ily|love|romance|smile|you		
smileys	😘	0.6	face blowing a kiss	adorbs|bae|flirt|heart|ily|love|lover|miss|muah|romantic|smooch|xoxo|you		
smileys	😗	1.0	kissing face	143|date|dating|flirt|ily|kiss|love|smooch|smooches|xoxo|you		
smileys	😙	1.0	kissing face with smiling eyes	143|closed|date|dating|eye|flirt|ily|kiss|kisses|love|night|smile		
smileys	😚	0.6	kissing face with closed eyes	143|bae|blush|date|dating|eye|flirt|ily|kisses|smooches|xoxo		
smileys	😋	0.6	face savoring food	delicious|eat|full|hungry|savor|smile|smiling|tasty|um|yum|yummy		
smileys	😛	1.0	face with tongue	awesome|cool|nice|party|stuck-out|sweet		
smileys	😝	0.6	squinting face with tongue	closed|eye|eyes|gross|horrible|omg|stuck-out|taste|whatever|yolo		
smileys	😜	0.6	winking face with tongue	crazy|epic|eye|funny|joke|loopy|nutty|party|stuck-out|wacky|weirdo|wink|yolo		
smileys	🤪	5.0	zany face	crazy|eye|eyes|goofy|large|small		
smileys	🤨	5.0	face with raised eyebrow	disapproval|disbelief|distrust|emoji|hmm|mild|skeptic|skeptical|skepticism|surprise|what		
smileys	🧐	5.0	face with monocle	classy|fancy|rich|stuffy|wealthy		
smileys	🤓	1.0	nerd face	brainy|clever|expert|geek|gifted|glasses|intelligent|smart		
smileys	😎	1.0	smiling face with sunglasses	awesome|beach|bright|bro|chilling|cool|rad|relaxed|shades|slay|smile|style|swag|win		
smileys	🥸	13.0	disguised face	disguise|eyebrow|glasses|incognito|moustache|mustache|nose|person|spy|tache|tash		
smileys	🤩	5.0	star-struck	excited|eyes|face|grinning|smile|starry-eyed|wow		
smileys	🥳	11.0	partying face	bday|birthday|celebrate|celebration|excited|happy|hat|hooray|horn|party		
smileys	🙂‍↕️	15.1	head shaking vertically	nod|yes		
smileys	😏	0.6	smirking face	boss|dapper|flirt|homie|kidding|leer|shade|slick|sly|smirk|smug|snicker|suave|suspicious|swag		
smileys	😒	0.6	unamused face	bored|fine|jealous|jel|jelly|pissed|smh|ugh|uhh|unhappy|weird|whatever		
smileys	🙂‍↔️	15.1	head shaking horizontally	no|shake		
smileys	😞	0.6	disappointed face	awful|blame|dejected|fail|losing|sad|unhappy		
smileys	😔	0.6	pensive face	awful|bored|dejected|died|disappointed|losing|lost|sad|sucks		
smileys	😟	1.0	worried face	anxious|butterflies|nerves|nervous|sad|stress|stressed|surprised|worry		
smileys	😕	1.0	confused face	befuddled|confusing|dunno|frown|hm|meh|not|sad|sorry|sure		
smileys	🙁	1.0	slightly frowning face	frown|sad		
smileys	☹️	0.7	frowning face	frown|sad		
smileys	😣	0.6	persevering face	concentrate|concentration|focus|headache|persevere		
smileys	😖	0.6	confounded face	annoyed|confused|cringe|distraught|feels|frustrated|mad|sad		
smileys	😫	0.6	tired face	cost|feels|nap|sad|sneeze		
smileys	😩	0.6	weary face	crying|fail|feels|hungry|mad|nooo|sad|sleepy|tired|unhappy		
smileys	🥺	11.0	pleading face	begging|big|eyes|mercy|not|please|pretty|puppy|sad|why		
smileys	😢	0.6	crying face	awful|cry|feels|miss|sad|tear|triste|unhappy		
smileys	😭	0.6	loudly crying face	bawling|cry|sad|sob|tear|tears|unhappy		
smileys	😤	0.6	face with steam from nose	anger|angry|feels|fume|fuming|furious|fury|mad|triumph|unhappy|won		
smileys	😠	0.6	angry face	anger|blame|feels|frustrated|mad|maddening|rage|shade|unhappy|upset		
smileys	😡	0.6	enraged face	anger|angry|feels|mad|maddening|pouting|rage|red|shade|unhappy|upset		
smileys	🤬	5.0	face with symbols on mouth	censor|cursing|cussing|mad|pissed|swearing		
smileys	🤯	5.0	exploding head	blown|explode|mind|mindblown|no|shocked|way		
smileys	😳	0.6	flushed face	amazed|awkward|crazy|dazed|dead|disbelief|embarrassed|geez|heat|hot|impressed|jeez|what|wow		
smileys	🥵	11.0	hot face	dying|feverish|heat|panting|red-faced|stroke|sweating|tongue		
smileys	🥶	11.0	cold face	blue|blue-faced|freezing|frostbite|icicles|subzero|teeth		
smileys	😶‍🌫️	13.1	face in clouds	absentminded|fog|head		
smileys	😱	0.6	face screaming in fear	epic|fearful|munch|scared|scream|screamer|shocked|surprised|woah		
smileys	😨	0.6	fearful face	afraid|anxious|blame|fear|scared|worried		
smileys	😰	0.6	anxious face with sweat	blue|cold|eek|mouth|nervous|open|rushed|scared|yikes		
smileys	😥	0.6	sad but relieved face	anxious|call|close|complicated|disappointed|not|sweat|time|whew		
smileys	😓	0.6	downcast face with sweat	close|cold|feels|headache|nervous|sad|scared|yikes		
smileys	🤗	1.0	smiling face with open hands	hug|hugging		
smileys	🤔	1.0	thinking face	chin|consider|hmm|ponder|pondering|wondering		
smileys	🫣	14.0	face with peeking eye	captivated|embarrass|hide|hiding|peek|peep|scared|shy|stare		
smileys	🤭	5.0	face with hand over mouth	giggle|giggling|oops|realization|secret|shock|sudden|surprise|whoops		
smileys	🫢	14.0	face with open eyes and hand over mouth	amazement|awe|disbelief|embarrass|gasp|omg|quiet|scared|shock|surprise		
smileys	🫡	14.0	saluting face	good|luck|ma’am|ok|respect|salute|sir|troops|yes		
smileys	🤫	5.0	shushing face	quiet|shh|shush		
smileys	🫠	14.0	melting face	disappear|dissolve|embarrassed|haha|heat|hot|liquid|lol|melt|sarcasm|sarcastic		
smileys	🤥	3.0	lying face	liar|lie|pinocchio		
smileys	😶	1.0	face without mouth	awkward|blank|expressionless|mouthless|mute|quiet|secret|silence|silent|speechless		
smileys	🫥	14.0	dotted line face	depressed|disappear|hidden|hide|introvert|invisible|meh|whatever|wtv		
smileys	😐	0.7	neutral face	awkward|blank|deadpan|expressionless|fine|jealous|meh|oh|shade|straight|unamused|unhappy|unimpressed|whatever		
smileys	🫤	14.0	face with diagonal mouth	confused|confusion|disappointed|doubt|doubtful|frustrated|frustration|meh|skeptical|unsure|whatever|wtv		
smileys	😑	1.0	expressionless face	awkward|dead|fine|inexpressive|jealous|meh|not|oh|omg|straight|uh|unhappy|unimpressed|whatever		
smileys	🫨	15.0	shaking face	crazy|daze|earthquake|omg|panic|shock|surprise|vibrate|whoa|wow		
smileys	😬	1.0	grimacing face	awk|awkward|dentist|grimace|grinning|smile|smiling		
smileys	🙄	1.0	face with rolling eyes	eyeroll|shade|ugh|whatever		
smileys	😯	1.0	hushed face	epic|omg|stunned|surprised|whoa|woah		
smileys	😦	1.0	frowning face with open mouth	caught|frown|guard|scared|scary|surprise|what|wow		
smileys	😧	1.0	anguished face	forgot|scared|scary|stressed|surprise|unhappy|what|wow		
smileys	😮	1.0	face with open mouth	believe|forgot|omg|shocked|surprised|sympathy|unbelievable|unreal|whoa|wow|you		
smileys	😲	0.6	astonished face	cost|no|omg|shocked|totally|way		
smileys	🥱	12.0	yawning face	bedtime|bored|goodnight|nap|night|sleep|sleepy|tired|whatever|yawn|zzz		
smileys	🫩	16.0	face with bags under eyes	bored|exhausted|fatigued|late|sleepy|tired|weary		
smileys	🫪	17.0	distorted face	anxiety|bloated|panic|shocked|surprised|vulnerable		
smileys	😴	1.0	sleeping face	bed|bedtime|good|goodnight|nap|night|sleep|tired|whatever|yawn|zzz		
smileys	🤤	3.0	drooling face			
smileys	😪	0.6	sleepy face	crying|good|night|sad|sleep|sleeping|tired		
smileys	😮‍💨	13.1	face exhaling	blow|blowing|exhale|exhausted|gasp|groan|relief|sigh|smiley|smoke|whisper|whistle		
smileys	😵	0.6	face with crossed-out eyes	dead|dizzy|feels|knocked|sick|tired		
smileys	😵‍💫	13.1	face with spiral eyes	confused|dizzy|hypnotized|omg|smiley|trouble|whoa|woah|woozy		
smileys	🤐	1.0	zipper-mouth face	keep|quiet|secret|shut|zip		
smileys	🥴	11.0	woozy face	dizzy|drunk|eyes|intoxicated|mouth|tipsy|uneven|wavy		
smileys	🤢	3.0	nauseated face	gross|nasty|sick|vomit		
smileys	🤮	5.0	face vomiting	barf|ew|gross|puke|sick|spew|throw|up|vomit		
smileys	🤧	3.0	sneezing face	fever|flu|gesundheit|sick|sneeze		
smileys	😷	0.6	face with medical mask	cold|dentist|dermatologist|doctor|dr|germs|medicine|sick		
smileys	🤒	1.0	face with thermometer	ill|sick		
smileys	🤕	1.0	face with head-bandage	hurt|injury|ouch		
smileys	🤑	1.0	money-mouth face	paid		
smileys	🤠	3.0	cowboy hat face	cowgirl		
smileys	😈	1.0	smiling face with horns	demon|devil|evil|fairy|fairytale|fantasy|purple|shade|smile|tale		
smileys	👿	0.6	angry face with horns	demon|devil|evil|fairy|fairytale|fantasy|imp|mischievous|purple|shade|tale		
smileys	👹	0.6	ogre	creature|devil|face|fairy|fairytale|fantasy|mask|monster|scary|tale		
smileys	👺	0.6	goblin	angry|creature|face|fairy|fairytale|fantasy|mask|mean|monster|tale		
smileys	🤡	3.0	clown face			
smileys	💩	0.6	pile of poo	bs|comic|doo|dung|face|fml|monster|poop|smelly|smh|stink|stinks|stinky|turd		
smileys	👻	0.6	ghost	boo|creature|excited|face|fairy|fairytale|fantasy|halloween|haunting|monster|scary|silly|tale		
smileys	💀	0.6	skull	body|dead|death|face|fairy|fairytale|i’m|lmao|monster|tale|yolo		
smileys	☠️	1.0	skull and crossbones	bone|dead|death|face|monster		
smileys	👽	0.6	alien	creature|extraterrestrial|face|fairy|fairytale|fantasy|monster|space|tale|ufo		
smileys	👾	0.6	alien monster	creature|extraterrestrial|face|fairy|fairytale|fantasy|game|gamer|games|pixelated|space|tale|ufo		
smileys	🤖	1.0	robot	face|monster		
smileys	🎃	0.6	jack-o-lantern	celebration|halloween|pumpkin		
smileys	😺	0.6	grinning cat	animal|face|mouth|open|smile|smiling		
smileys	😸	0.6	grinning cat with smiling eyes	animal|eye|face|grin|smile		
smileys	😹	0.6	cat with tears of joy	animal|face|laugh|laughing|lol|tear		
smileys	😻	0.6	smiling cat with heart-eyes	animal|eye|face|love|smile		
smileys	😼	0.6	cat with wry smile	animal|face|ironic		
smileys	😽	0.6	kissing cat	animal|closed|eye|eyes|face|kiss		
smileys	🙀	0.6	weary cat	animal|face|oh|surprised		
smileys	😿	0.6	crying cat	animal|cry|face|sad|tear		
smileys	😾	0.6	pouting cat	animal|face		
smileys	🫶	14.0	heart hands	<3|love|you	🫶🏻,🫶🏼,🫶🏽,🫶🏾,🫶🏿	14.0
smileys	🤲	5.0	palms up together	cupped|dua|hands|pray|prayer|wish	🤲🏻,🤲🏼,🤲🏽,🤲🏾,🤲🏿	5.0
smileys	👐	0.6	open hands	hand|hug|jazz|swerve	👐🏻,👐🏼,👐🏽,👐🏾,👐🏿	1.0
smileys	🙌	0.6	raising hands	celebration|gesture|hand|hooray|praise|raised	🙌🏻,🙌🏼,🙌🏽,🙌🏾,🙌🏿	1.0
smileys	👏	0.6	clapping hands	applause|approval|awesome|clap|congrats|congratulations|excited|good|great|hand|homie|job|nice|prayed|well|yay	👏🏻,👏🏼,👏🏽,👏🏾,👏🏿	1.0
smileys	🤝	3.0	handshake	agreement|deal|hand|meeting|shake	🤝🏻,🤝🏼,🤝🏽,🤝🏾,🤝🏿,🫱🏻‍🫲🏼,🫱🏻‍🫲🏽,🫱🏻‍🫲🏾,🫱🏻‍🫲🏿,🫱🏼‍🫲🏻,🫱🏼‍🫲🏽,🫱🏼‍🫲🏾,🫱🏼‍🫲🏿,🫱🏽‍🫲🏻,🫱🏽‍🫲🏼,🫱🏽‍🫲🏾,🫱🏽‍🫲🏿,🫱🏾‍🫲🏻,🫱🏾‍🫲🏼,🫱🏾‍🫲🏽,🫱🏾‍🫲🏿,🫱🏿‍🫲🏻,🫱🏿‍🫲🏼,🫱🏿‍🫲🏽,🫱🏿‍🫲🏾	14.0
smileys	👍	0.6	thumbs up	+1|good|hand|like|thumb|yes	👍🏻,👍🏼,👍🏽,👍🏾,👍🏿	1.0
smileys	👎	0.6	thumbs down	-1|bad|dislike|good|hand|no|nope|thumb	👎🏻,👎🏼,👎🏽,👎🏾,👎🏿	1.0
smileys	👊	0.6	oncoming fist	absolutely|agree|boom|bro|bruh|bump|clenched|correct|hand|knuckle|pound|punch|rock|ttyl	👊🏻,👊🏼,👊🏽,👊🏾,👊🏿	1.0
smileys	✊	0.6	raised fist	clenched|hand|punch|solidarity	✊🏻,✊🏼,✊🏽,✊🏾,✊🏿	1.0
smileys	🤛	3.0	left-facing fist	leftwards	🤛🏻,🤛🏼,🤛🏽,🤛🏾,🤛🏿	3.0
smileys	🤜	3.0	right-facing fist	rightwards	🤜🏻,🤜🏼,🤜🏽,🤜🏾,🤜🏿	3.0
smileys	🫷	15.0	leftwards pushing hand	block|five|halt|high|hold|leftward|pause|push|refuse|slap|stop|wait	🫷🏻,🫷🏼,🫷🏽,🫷🏾,🫷🏿	15.0
smileys	🫸	15.0	rightwards pushing hand	block|five|halt|high|hold|pause|push|refuse|rightward|slap|stop|wait	🫸🏻,🫸🏼,🫸🏽,🫸🏾,🫸🏿	15.0
smileys	🤞	3.0	crossed fingers	cross|finger|hand|luck	🤞🏻,🤞🏼,🤞🏽,🤞🏾,🤞🏿	3.0
smileys	✌️	0.6	victory hand	peace|v	✌🏻,✌🏼,✌🏽,✌🏾,✌🏿	1.0
smileys	🫰	14.0	hand with index finger and thumb crossed	<3|expensive|heart|love|money|snap	🫰🏻,🫰🏼,🫰🏽,🫰🏾,🫰🏿	14.0
smileys	🤟	5.0	love-you gesture	fingers|hand|ily|three	🤟🏻,🤟🏼,🤟🏽,🤟🏾,🤟🏿	5.0
smileys	🤘	1.0	sign of the horns	finger|hand|rock-on	🤘🏻,🤘🏼,🤘🏽,🤘🏾,🤘🏿	1.0
smileys	👌	0.6	OK hand	awesome|bet|dope|fleek|fosho|got|gotcha|legit|okay|pinch|rad|sure|sweet|three	👌🏻,👌🏼,👌🏽,👌🏾,👌🏿	1.0
smileys	🤌	13.0	pinched fingers	gesture|hand|hold|huh|interrogation|patience|relax|sarcastic|ugh|what|zip	🤌🏻,🤌🏼,🤌🏽,🤌🏾,🤌🏿	13.0
smileys	🤏	12.0	pinching hand	amount|bit|fingers|little|small|sort	🤏🏻,🤏🏼,🤏🏽,🤏🏾,🤏🏿	12.0
smileys	🫳	14.0	palm down hand	dismiss|drop|dropped|pick|shoo|up	🫳🏻,🫳🏼,🫳🏽,🫳🏾,🫳🏿	14.0
smileys	🫴	14.0	palm up hand	beckon|catch|come|hold|know|lift|me|offer|tell	🫴🏻,🫴🏼,🫴🏽,🫴🏾,🫴🏿	14.0
smileys	👈	0.6	backhand index pointing left	finger|hand|point	👈🏻,👈🏼,👈🏽,👈🏾,👈🏿	1.0
smileys	👉	0.6	backhand index pointing right	finger|hand|point	👉🏻,👉🏼,👉🏽,👉🏾,👉🏿	1.0
smileys	👆	0.6	backhand index pointing up	finger|hand|point	👆🏻,👆🏼,👆🏽,👆🏾,👆🏿	1.0
smileys	👇	0.6	backhand index pointing down	finger|hand|point	👇🏻,👇🏼,👇🏽,👇🏾,👇🏿	1.0
smileys	☝️	0.6	index pointing up	finger|hand|point|this	☝🏻,☝🏼,☝🏽,☝🏾,☝🏿	1.0
smileys	✋	0.6	raised hand	5|five|high|stop	✋🏻,✋🏼,✋🏽,✋🏾,✋🏿	1.0
smileys	🤚	3.0	raised back of hand	backhand	🤚🏻,🤚🏼,🤚🏽,🤚🏾,🤚🏿	3.0
smileys	🖐️	0.7	hand with fingers splayed	finger|raised|stop	🖐🏻,🖐🏼,🖐🏽,🖐🏾,🖐🏿	1.0
smileys	🖖	1.0	vulcan salute	finger|hand|hands	🖖🏻,🖖🏼,🖖🏽,🖖🏾,🖖🏿	1.0
smileys	👋	0.6	waving hand	bye|cya|g2g|greetings|gtg|hello|hey|hi|later|outtie|ttfn|ttyl|wave|yo|you	👋🏻,👋🏼,👋🏽,👋🏾,👋🏿	1.0
smileys	🤙	3.0	call me hand	hang|loose|shaka	🤙🏻,🤙🏼,🤙🏽,🤙🏾,🤙🏿	3.0
smileys	🫲	14.0	leftwards hand	handshake|hold|left|leftward|reach|shake	🫲🏻,🫲🏼,🫲🏽,🫲🏾,🫲🏿	14.0
smileys	🫱	14.0	rightwards hand	handshake|hold|reach|right|rightward|shake	🫱🏻,🫱🏼,🫱🏽,🫱🏾,🫱🏿	14.0
smileys	💪	0.6	flexed biceps	arm|beast|bench|bodybuilder|bro|curls|flex|gains|gym|jacked|muscle|press|ripped|strong|weightlift	💪🏻,💪🏼,💪🏽,💪🏾,💪🏿	1.0
smileys	🦾	12.0	mechanical arm	accessibility|prosthetic		
smileys	🖕	1.0	middle finger	hand	🖕🏻,🖕🏼,🖕🏽,🖕🏾,🖕🏿	1.0
smileys	✍️	0.7	writing hand	write	✍🏻,✍🏼,✍🏽,✍🏾,✍🏿	1.0
smileys	🙏	0.6	folded hands	appreciate|ask|beg|blessed|bow|cmon|five|gesture|hand|high|please|pray|thanks|thx	🙏🏻,🙏🏼,🙏🏽,🙏🏾,🙏🏿	1.0
smileys	🫵	14.0	index pointing at the viewer	finger|hand|poke|you	🫵🏻,🫵🏼,🫵🏽,🫵🏾,🫵🏿	14.0
smileys	🦶	11.0	foot	ankle|feet|kick|stomp	🦶🏻,🦶🏼,🦶🏽,🦶🏾,🦶🏿	11.0
smileys	🦵	11.0	leg	bent|foot|kick|knee|limb	🦵🏻,🦵🏼,🦵🏽,🦵🏾,🦵🏿	11.0
smileys	🦿	12.0	mechanical leg	accessibility|prosthetic		
smileys	💄	0.6	lipstick	cosmetics|date|makeup		
smileys	💋	0.6	kiss mark	dating|emotion|heart|kissing|lips|romance|sexy		
smileys	👄	0.6	mouth	beauty|body|kiss|kissing|lips|lipstick		
smileys	🫦	14.0	biting lip	anxious|bite|fear|flirt|flirting|kiss|lipstick|nervous|sexy|uncomfortable|worried|worry		
smileys	🦷	11.0	tooth	dentist|pearly|teeth|white		
smileys	👅	0.6	tongue	body|lick|slurp		
smileys	👂	0.6	ear	body|ears|hear|hearing|listen|listening|sound	👂🏻,👂🏼,👂🏽,👂🏾,👂🏿	1.0
smileys	🦻	12.0	ear with hearing aid	accessibility|hard	🦻🏻,🦻🏼,🦻🏽,🦻🏾,🦻🏿	12.0
smileys	👃	0.6	nose	body|noses|nosey|odor|smell|smells	👃🏻,👃🏼,👃🏽,👃🏾,👃🏿	1.0
smileys	🫆	16.0	fingerprint	clue|crime|detective|forensics|identity|mystery|print|safety|trace		
smileys	👣	0.6	footprints	barefoot|clothing|footprint|omw|print|walk		
smileys	👁️	0.7	eye	1|body|one		
smileys	👀	0.6	eyes	body|eye|face|googly|look|looking|omg|peep|see|seeing		
smileys	🫀	13.0	anatomical heart	beat|cardiology|heartbeat|organ|pulse|real|red		
smileys	🫁	13.0	lungs	breath|breathe|exhalation|inhalation|lung|organ|respiration		
smileys	🧠	5.0	brain	intelligent|smart		
smileys	🗣️	0.7	speaking head	face|silhouette|speak		
smileys	👤	0.6	bust in silhouette	mysterious|shadow		
smileys	👥	1.0	busts in silhouette	bff|bust|everyone|friend|friends|people		
smileys	🫂	13.0	people hugging	comfort|embrace|farewell|friendship|goodbye|hello|hug|love|thanks		
smileys	👶	0.6	baby	babies|children|goo|infant|newborn|pregnant|young	👶🏻,👶🏼,👶🏽,👶🏾,👶🏿	1.0
smileys	👧	0.6	girl	bright-eyed|child|daughter|granddaughter|kid|virgo|young|younger|zodiac	👧🏻,👧🏼,👧🏽,👧🏾,👧🏿	1.0
smileys	🧒	5.0	child	bright-eyed|grandchild|kid|young|younger	🧒🏻,🧒🏼,🧒🏽,🧒🏾,🧒🏿	5.0
smileys	👦	0.6	boy	bright-eyed|child|grandson|kid|son|young|younger	👦🏻,👦🏼,👦🏽,👦🏾,👦🏿	1.0
smileys	👩	0.6	woman	adult|lady	👩🏻,👩🏼,👩🏽,👩🏾,👩🏿	1.0
smileys	🧑	5.0	person	adult	🧑🏻,🧑🏼,🧑🏽,🧑🏾,🧑🏿	5.0
smileys	👨	0.6	man	adult|bro	👨🏻,👨🏼,👨🏽,👨🏾,👨🏿	1.0
smileys	👩‍🦱	11.0	woman: curly hair	adult|lady	👩🏻‍🦱,👩🏼‍🦱,👩🏽‍🦱,👩🏾‍🦱,👩🏿‍🦱	11.0
smileys	🧑‍🦱	12.1	person: curly hair	adult	🧑🏻‍🦱,🧑🏼‍🦱,🧑🏽‍🦱,🧑🏾‍🦱,🧑🏿‍🦱	12.1
smileys	👨‍🦱	11.0	man: curly hair	adult|bro	👨🏻‍🦱,👨🏼‍🦱,👨🏽‍🦱,👨🏾‍🦱,👨🏿‍🦱	11.0
smileys	👩‍🦰	11.0	woman: red hair	adult|lady	👩🏻‍🦰,👩🏼‍🦰,👩🏽‍🦰,👩🏾‍🦰,👩🏿‍🦰	11.0
smileys	🧑‍🦰	12.1	person: red hair	adult	🧑🏻‍🦰,🧑🏼‍🦰,🧑🏽‍🦰,🧑🏾‍🦰,🧑🏿‍🦰	12.1
smileys	👨‍🦰	11.0	man: red hair	adult|bro	👨🏻‍🦰,👨🏼‍🦰,👨🏽‍🦰,👨🏾‍🦰,👨🏿‍🦰	11.0
smileys	👱‍♀️	4.0	woman: blond hair	blond-haired|blonde	👱🏻‍♀️,👱🏼‍♀️,👱🏽‍♀️,👱🏾‍♀️,👱🏿‍♀️	4.0
smileys	👱	0.6	person: blond hair	blond-haired|human	👱🏻,👱🏼,👱🏽,👱🏾,👱🏿	1.0
smileys	👱‍♂️	4.0	man: blond hair	blond-haired	👱🏻‍♂️,👱🏼‍♂️,👱🏽‍♂️,👱🏾‍♂️,👱🏿‍♂️	4.0
smileys	👩‍🦳	11.0	woman: white hair	adult|lady	👩🏻‍🦳,👩🏼‍🦳,👩🏽‍🦳,👩🏾‍🦳,👩🏿‍🦳	11.0
smileys	🧑‍🦳	12.1	person: white hair	adult	🧑🏻‍🦳,🧑🏼‍🦳,🧑🏽‍🦳,🧑🏾‍🦳,🧑🏿‍🦳	12.1
smileys	👨‍🦳	11.0	man: white hair	adult|bro	👨🏻‍🦳,👨🏼‍🦳,👨🏽‍🦳,👨🏾‍🦳,👨🏿‍🦳	11.0
smileys	👩‍🦲	11.0	woman: bald	adult|lady	👩🏻‍🦲,👩🏼‍🦲,👩🏽‍🦲,👩🏾‍🦲,👩🏿‍🦲	11.0
smileys	🧑‍🦲	12.1	person: bald	adult	🧑🏻‍🦲,🧑🏼‍🦲,🧑🏽‍🦲,🧑🏾‍🦲,🧑🏿‍🦲	12.1
smileys	👨‍🦲	11.0	man: bald	adult|bro	👨🏻‍🦲,👨🏼‍🦲,👨🏽‍🦲,👨🏾‍🦲,👨🏿‍🦲	11.0
smileys	🧔‍♀️	13.1	woman: beard	bearded|whiskers	🧔🏻‍♀️,🧔🏼‍♀️,🧔🏽‍♀️,🧔🏾‍♀️,🧔🏿‍♀️	13.1
smileys	🧔	5.0	person: beard	bearded|whiskers	🧔🏻,🧔🏼,🧔🏽,🧔🏾,🧔🏿	5.0
smileys	🧔‍♂️	13.1	man: beard	bearded|whiskers	🧔🏻‍♂️,🧔🏼‍♂️,🧔🏽‍♂️,🧔🏾‍♂️,🧔🏿‍♂️	13.1
smileys	👵	0.6	old woman	adult|elderly|grandma|grandmother|granny|lady|wise	👵🏻,👵🏼,👵🏽,👵🏾,👵🏿	1.0
smileys	🧓	5.0	older person	adult|elderly|grandparent|old|wise	🧓🏻,🧓🏼,🧓🏽,🧓🏾,🧓🏿	5.0
smileys	👴	0.6	old man	adult|bald|elderly|gramps|grandfather|grandpa|wise	👴🏻,👴🏼,👴🏽,👴🏾,👴🏿	1.0
smileys	👲	0.6	person with skullcap	cap|chinese|gua|guapi|hat|mao|pi	👲🏻,👲🏼,👲🏽,👲🏾,👲🏿	1.0
smileys	👳‍♀️	4.0	woman wearing turban		👳🏻‍♀️,👳🏼‍♀️,👳🏽‍♀️,👳🏾‍♀️,👳🏿‍♀️	4.0
smileys	👳	0.6	person wearing turban		👳🏻,👳🏼,👳🏽,👳🏾,👳🏿	1.0
smileys	👳‍♂️	4.0	man wearing turban		👳🏻‍♂️,👳🏼‍♂️,👳🏽‍♂️,👳🏾‍♂️,👳🏿‍♂️	4.0
smileys	🧕	5.0	woman with headscarf	bandana|head|hijab|kerchief|mantilla|tichel	🧕🏻,🧕🏼,🧕🏽,🧕🏾,🧕🏿	5.0
smileys	👮‍♀️	4.0	woman police officer	apprehend|arrest|citation|cop|law|over|pulled|undercover	👮🏻‍♀️,👮🏼‍♀️,👮🏽‍♀️,👮🏾‍♀️,👮🏿‍♀️	4.0
smileys	👮	0.6	police officer	apprehend|arrest|citation|cop|law|over|pulled|undercover	👮🏻,👮🏼,👮🏽,👮🏾,👮🏿	1.0
smileys	👮‍♂️	4.0	man police officer	apprehend|arrest|citation|cop|law|over|pulled|undercover	👮🏻‍♂️,👮🏼‍♂️,👮🏽‍♂️,👮🏾‍♂️,👮🏿‍♂️	4.0
smileys	👷‍♀️	4.0	woman construction worker	build|fix|hardhat|hat|man|rebuild|remodel|repair|work	👷🏻‍♀️,👷🏼‍♀️,👷🏽‍♀️,👷🏾‍♀️,👷🏿‍♀️	4.0
smileys	👷	0.6	construction worker	build|fix|hardhat|hat|man|person|rebuild|remodel|repair|work	👷🏻,👷🏼,👷🏽,👷🏾,👷🏿	1.0
smileys	👷‍♂️	4.0	man construction worker	build|fix|hardhat|hat|rebuild|remodel|repair|work	👷🏻‍♂️,👷🏼‍♂️,👷🏽‍♂️,👷🏾‍♂️,👷🏿‍♂️	4.0
smileys	💂‍♀️	4.0	woman guard	buckingham|helmet|london|palace	💂🏻‍♀️,💂🏼‍♀️,💂🏽‍♀️,💂🏾‍♀️,💂🏿‍♀️	4.0
smileys	💂	0.6	guard	buckingham|helmet|london|palace	💂🏻,💂🏼,💂🏽,💂🏾,💂🏿	1.0
smileys	💂‍♂️	4.0	man guard	buckingham|helmet|london|palace	💂🏻‍♂️,💂🏼‍♂️,💂🏽‍♂️,💂🏾‍♂️,💂🏿‍♂️	4.0
smileys	🕵️‍♀️	4.0	woman detective	sleuth|spy	🕵🏻‍♀️,🕵🏼‍♀️,🕵🏽‍♀️,🕵🏾‍♀️,🕵🏿‍♀️	4.0
smileys	🕵️	0.7	detective	sleuth|spy	🕵🏻,🕵🏼,🕵🏽,🕵🏾,🕵🏿	2.0
smileys	🕵️‍♂️	4.0	man detective	sleuth|spy	🕵🏻‍♂️,🕵🏼‍♂️,🕵🏽‍♂️,🕵🏾‍♂️,🕵🏿‍♂️	4.0
smileys	👩‍⚕️	4.0	woman health worker	doctor|healthcare|nurse|therapist	👩🏻‍⚕️,👩🏼‍⚕️,👩🏽‍⚕️,👩🏾‍⚕️,👩🏿‍⚕️	4.0
smileys	🧑‍⚕️	12.1	health worker	doctor|healthcare|nurse|therapist	🧑🏻‍⚕️,🧑🏼‍⚕️,🧑🏽‍⚕️,🧑🏾‍⚕️,🧑🏿‍⚕️	12.1
smileys	👨‍⚕️	4.0	man health worker	doctor|healthcare|nurse|therapist	👨🏻‍⚕️,👨🏼‍⚕️,👨🏽‍⚕️,👨🏾‍⚕️,👨🏿‍⚕️	4.0
smileys	👩‍🌾	4.0	woman farmer	gardener|rancher	👩🏻‍🌾,👩🏼‍🌾,👩🏽‍🌾,👩🏾‍🌾,👩🏿‍🌾	4.0
smileys	🧑‍🌾	12.1	farmer	gardener|rancher	🧑🏻‍🌾,🧑🏼‍🌾,🧑🏽‍🌾,🧑🏾‍🌾,🧑🏿‍🌾	12.1
smileys	👨‍🌾	4.0	man farmer	gardener|rancher	👨🏻‍🌾,👨🏼‍🌾,👨🏽‍🌾,👨🏾‍🌾,👨🏿‍🌾	4.0
smileys	👩‍🍳	4.0	woman cook	chef	👩🏻‍🍳,👩🏼‍🍳,👩🏽‍🍳,👩🏾‍🍳,👩🏿‍🍳	4.0
smileys	🧑‍🍳	12.1	cook	chef	🧑🏻‍🍳,🧑🏼‍🍳,🧑🏽‍🍳,🧑🏾‍🍳,🧑🏿‍🍳	12.1
smileys	👨‍🍳	4.0	man cook	chef	👨🏻‍🍳,👨🏼‍🍳,👨🏽‍🍳,👨🏾‍🍳,👨🏿‍🍳	4.0
smileys	👩‍🎓	4.0	woman student	graduate	👩🏻‍🎓,👩🏼‍🎓,👩🏽‍🎓,👩🏾‍🎓,👩🏿‍🎓	4.0
smileys	🧑‍🎓	12.1	student	graduate	🧑🏻‍🎓,🧑🏼‍🎓,🧑🏽‍🎓,🧑🏾‍🎓,🧑🏿‍🎓	12.1
smileys	👨‍🎓	4.0	man student	graduate	👨🏻‍🎓,👨🏼‍🎓,👨🏽‍🎓,👨🏾‍🎓,👨🏿‍🎓	4.0
smileys	👩‍🎤	4.0	woman singer	actor|entertainer|rock|rockstar|star	👩🏻‍🎤,👩🏼‍🎤,👩🏽‍🎤,👩🏾‍🎤,👩🏿‍🎤	4.0
smileys	🧑‍🎤	12.1	singer	actor|entertainer|rock|rockstar|star	🧑🏻‍🎤,🧑🏼‍🎤,🧑🏽‍🎤,🧑🏾‍🎤,🧑🏿‍🎤	12.1
smileys	👨‍🎤	4.0	man singer	actor|entertainer|rock|rockstar|star	👨🏻‍🎤,👨🏼‍🎤,👨🏽‍🎤,👨🏾‍🎤,👨🏿‍🎤	4.0
smileys	👩‍🏫	4.0	woman teacher	instructor|lecturer|professor	👩🏻‍🏫,👩🏼‍🏫,👩🏽‍🏫,👩🏾‍🏫,👩🏿‍🏫	4.0
smileys	🧑‍🏫	12.1	teacher	instructor|lecturer|professor	🧑🏻‍🏫,🧑🏼‍🏫,🧑🏽‍🏫,🧑🏾‍🏫,🧑🏿‍🏫	12.1
smileys	👨‍🏫	4.0	man teacher	instructor|lecturer|professor	👨🏻‍🏫,👨🏼‍🏫,👨🏽‍🏫,👨🏾‍🏫,👨🏿‍🏫	4.0
smileys	👩‍🏭	4.0	woman factory worker	assembly|industrial	👩🏻‍🏭,👩🏼‍🏭,👩🏽‍🏭,👩🏾‍🏭,👩🏿‍🏭	4.0
smileys	🧑‍🏭	12.1	factory worker	assembly|industrial	🧑🏻‍🏭,🧑🏼‍🏭,🧑🏽‍🏭,🧑🏾‍🏭,🧑🏿‍🏭	12.1
smileys	👨‍🏭	4.0	man factory worker	assembly|industrial	👨🏻‍🏭,👨🏼‍🏭,👨🏽‍🏭,👨🏾‍🏭,👨🏿‍🏭	4.0
smileys	👩‍💻	4.0	woman technologist	coder|computer|developer|inventor|software	👩🏻‍💻,👩🏼‍💻,👩🏽‍💻,👩🏾‍💻,👩🏿‍💻	4.0
smileys	🧑‍💻	12.1	technologist	coder|computer|developer|inventor|software	🧑🏻‍💻,🧑🏼‍💻,🧑🏽‍💻,🧑🏾‍💻,🧑🏿‍💻	12.1
smileys	👨‍💻	4.0	man technologist	coder|computer|developer|inventor|software	👨🏻‍💻,👨🏼‍💻,👨🏽‍💻,👨🏾‍💻,👨🏿‍💻	4.0
smileys	👩‍💼	4.0	woman office worker	architect|business|manager|white-collar	👩🏻‍💼,👩🏼‍💼,👩🏽‍💼,👩🏾‍💼,👩🏿‍💼	4.0
smileys	🧑‍💼	12.1	office worker	architect|business|manager|white-collar	🧑🏻‍💼,🧑🏼‍💼,🧑🏽‍💼,🧑🏾‍💼,🧑🏿‍💼	12.1
smileys	👨‍💼	4.0	man office worker	architect|business|manager|white-collar	👨🏻‍💼,👨🏼‍💼,👨🏽‍💼,👨🏾‍💼,👨🏿‍💼	4.0
smileys	👩‍🔧	4.0	woman mechanic	electrician|plumber|tradesperson	👩🏻‍🔧,👩🏼‍🔧,👩🏽‍🔧,👩🏾‍🔧,👩🏿‍🔧	4.0
smileys	🧑‍🔧	12.1	mechanic	electrician|plumber|tradesperson	🧑🏻‍🔧,🧑🏼‍🔧,🧑🏽‍🔧,🧑🏾‍🔧,🧑🏿‍🔧	12.1
smileys	👨‍🔧	4.0	man mechanic	electrician|plumber|tradesperson	👨🏻‍🔧,👨🏼‍🔧,👨🏽‍🔧,👨🏾‍🔧,👨🏿‍🔧	4.0
smileys	👩‍🔬	4.0	woman scientist	biologist|chemist|engineer|mathematician|physicist	👩🏻‍🔬,👩🏼‍🔬,👩🏽‍🔬,👩🏾‍🔬,👩🏿‍🔬	4.0
smileys	🧑‍🔬	12.1	scientist	biologist|chemist|engineer|mathematician|physicist	🧑🏻‍🔬,🧑🏼‍🔬,🧑🏽‍🔬,🧑🏾‍🔬,🧑🏿‍🔬	12.1
smileys	👨‍🔬	4.0	man scientist	biologist|chemist|engineer|mathematician|physicist	👨🏻‍🔬,👨🏼‍🔬,👨🏽‍🔬,👨🏾‍🔬,👨🏿‍🔬	4.0
smileys	👩‍🎨	4.0	woman artist	palette	👩🏻‍🎨,👩🏼‍🎨,👩🏽‍🎨,👩🏾‍🎨,👩🏿‍🎨	4.0
smileys	🧑‍🎨	12.1	artist	palette	🧑🏻‍🎨,🧑🏼‍🎨,🧑🏽‍🎨,🧑🏾‍🎨,🧑🏿‍🎨	12.1
smileys	👨‍🎨	4.0	man artist	palette	👨🏻‍🎨,👨🏼‍🎨,👨🏽‍🎨,👨🏾‍🎨,👨🏿‍🎨	4.0
smileys	👩‍🚒	4.0	woman firefighter	fire|firetruck	👩🏻‍🚒,👩🏼‍🚒,👩🏽‍🚒,👩🏾‍🚒,👩🏿‍🚒	4.0
smileys	🧑‍🚒	12.1	firefighter	fire|firetruck	🧑🏻‍🚒,🧑🏼‍🚒,🧑🏽‍🚒,🧑🏾‍🚒,🧑🏿‍🚒	12.1
smileys	👨‍🚒	4.0	man firefighter	fire|firetruck	👨🏻‍🚒,👨🏼‍🚒,👨🏽‍🚒,👨🏾‍🚒,👨🏿‍🚒	4.0
smileys	👩‍✈️	4.0	woman pilot	plane	👩🏻‍✈️,👩🏼‍✈️,👩🏽‍✈️,👩🏾‍✈️,👩🏿‍✈️	4.0
smileys	🧑‍✈️	12.1	pilot	plane	🧑🏻‍✈️,🧑🏼‍✈️,🧑🏽‍✈️,🧑🏾‍✈️,🧑🏿‍✈️	12.1
smileys	👨‍✈️	4.0	man pilot	plane	👨🏻‍✈️,👨🏼‍✈️,👨🏽‍✈️,👨🏾‍✈️,👨🏿‍✈️	4.0
smileys	👩‍🚀	4.0	woman astronaut	rocket|space	👩🏻‍🚀,👩🏼‍🚀,👩🏽‍🚀,👩🏾‍🚀,👩🏿‍🚀	4.0
smileys	🧑‍🚀	12.1	astronaut	rocket|space	🧑🏻‍🚀,🧑🏼‍🚀,🧑🏽‍🚀,🧑🏾‍🚀,🧑🏿‍🚀	12.1
smileys	👨‍🚀	4.0	man astronaut	rocket|space	👨🏻‍🚀,👨🏼‍🚀,👨🏽‍🚀,👨🏾‍🚀,👨🏿‍🚀	4.0
smileys	👩‍⚖️	4.0	woman judge	justice|law|scales	👩🏻‍⚖️,👩🏼‍⚖️,👩🏽‍⚖️,👩🏾‍⚖️,👩🏿‍⚖️	4.0
smileys	🧑‍⚖️	12.1	judge	justice|law|scales	🧑🏻‍⚖️,🧑🏼‍⚖️,🧑🏽‍⚖️,🧑🏾‍⚖️,🧑🏿‍⚖️	12.1
smileys	👨‍⚖️	4.0	man judge	justice|law|scales	👨🏻‍⚖️,👨🏼‍⚖️,👨🏽‍⚖️,👨🏾‍⚖️,👨🏿‍⚖️	4.0
smileys	👰‍♀️	13.0	woman with veil	bride|wedding	👰🏻‍♀️,👰🏼‍♀️,👰🏽‍♀️,👰🏾‍♀️,👰🏿‍♀️	13.0
smileys	👰	0.6	person with veil	wedding	👰🏻,👰🏼,👰🏽,👰🏾,👰🏿	1.0
smileys	👰‍♂️	13.0	man with veil	wedding	👰🏻‍♂️,👰🏼‍♂️,👰🏽‍♂️,👰🏾‍♂️,👰🏿‍♂️	13.0
smileys	🤵‍♀️	13.0	woman in tuxedo	formal|wedding	🤵🏻‍♀️,🤵🏼‍♀️,🤵🏽‍♀️,🤵🏾‍♀️,🤵🏿‍♀️	13.0
smileys	🤵	3.0	person in tuxedo	formal|wedding	🤵🏻,🤵🏼,🤵🏽,🤵🏾,🤵🏿	3.0
smileys	🤵‍♂️	13.0	man in tuxedo	formal|groom|wedding	🤵🏻‍♂️,🤵🏼‍♂️,🤵🏽‍♂️,🤵🏾‍♂️,🤵🏿‍♂️	13.0
smileys	👸	0.6	princess	crown|fairy|fairytale|fantasy|queen|royal|royalty|tale	👸🏻,👸🏼,👸🏽,👸🏾,👸🏿	1.0
smileys	🫅	14.0	person with crown	monarch|noble|regal|royal|royalty	🫅🏻,🫅🏼,🫅🏽,🫅🏾,🫅🏿	14.0
smileys	🤴	3.0	prince	crown|fairy|fairytale|fantasy|king|royal|royalty|tale	🤴🏻,🤴🏼,🤴🏽,🤴🏾,🤴🏿	3.0
smileys	🥷	13.0	ninja	assassin|fight|fighter|hidden|person|secret|skills|sly|soldier|stealth|war	🥷🏻,🥷🏼,🥷🏽,🥷🏾,🥷🏿	13.0
smileys	🦸‍♀️	11.0	woman superhero	good|hero|heroine|superpower	🦸🏻‍♀️,🦸🏼‍♀️,🦸🏽‍♀️,🦸🏾‍♀️,🦸🏿‍♀️	11.0
smileys	🦸	11.0	superhero	good|hero|superpower	🦸🏻,🦸🏼,🦸🏽,🦸🏾,🦸🏿	11.0
smileys	🦸‍♂️	11.0	man superhero	good|hero|superpower	🦸🏻‍♂️,🦸🏼‍♂️,🦸🏽‍♂️,🦸🏾‍♂️,🦸🏿‍♂️	11.0
smileys	🦹‍♀️	11.0	woman supervillain	bad|criminal|evil|superpower|villain	🦹🏻‍♀️,🦹🏼‍♀️,🦹🏽‍♀️,🦹🏾‍♀️,🦹🏿‍♀️	11.0
smileys	🦹	11.0	supervillain	bad|criminal|evil|superpower|villain	🦹🏻,🦹🏼,🦹🏽,🦹🏾,🦹🏿	11.0
smileys	🦹‍♂️	11.0	man supervillain	bad|criminal|evil|superpower|villain	🦹🏻‍♂️,🦹🏼‍♂️,🦹🏽‍♂️,🦹🏾‍♂️,🦹🏿‍♂️	11.0
smileys	🤶	3.0	Mrs. Claus	celebration|christmas|fairy|fantasy|holiday|merry|mother|santa|tale|xmas	🤶🏻,🤶🏼,🤶🏽,🤶🏾,🤶🏿	3.0
smileys	🧑‍🎄	13.0	Mx Claus	celebration|christmas|fairy|fantasy|holiday|merry|santa|tale|xmas	🧑🏻‍🎄,🧑🏼‍🎄,🧑🏽‍🎄,🧑🏾‍🎄,🧑🏿‍🎄	13.0
smileys	🎅	0.6	Santa Claus	celebration|christmas|fairy|fantasy|father|holiday|merry|tale|xmas	🎅🏻,🎅🏼,🎅🏽,🎅🏾,🎅🏿	1.0
smileys	🧙‍♀️	5.0	woman mage	fantasy|magic|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard	🧙🏻‍♀️,🧙🏼‍♀️,🧙🏽‍♀️,🧙🏾‍♀️,🧙🏿‍♀️	5.0
smileys	🧙	5.0	mage	fantasy|magic|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard	🧙🏻,🧙🏼,🧙🏽,🧙🏾,🧙🏿	5.0
smileys	🧙‍♂️	5.0	man mage	fantasy|magic|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard	🧙🏻‍♂️,🧙🏼‍♂️,🧙🏽‍♂️,🧙🏾‍♂️,🧙🏿‍♂️	5.0
smileys	🧝‍♀️	5.0	woman elf	elves|enchantment|fantasy|folklore|magic|magical|myth	🧝🏻‍♀️,🧝🏼‍♀️,🧝🏽‍♀️,🧝🏾‍♀️,🧝🏿‍♀️	5.0
smileys	🧝	5.0	elf	elves|enchantment|fantasy|folklore|magic|magical|myth	🧝🏻,🧝🏼,🧝🏽,🧝🏾,🧝🏿	5.0
smileys	🧝‍♂️	5.0	man elf	elves|enchantment|fantasy|folklore|magic|magical|myth	🧝🏻‍♂️,🧝🏼‍♂️,🧝🏽‍♂️,🧝🏾‍♂️,🧝🏿‍♂️	5.0
smileys	🧌	14.0	troll	fairy|fantasy|monster|tale|trolling		
smileys	🧛‍♀️	5.0	woman vampire	blood|fangs|halloween|scary|supernatural|teeth|undead	🧛🏻‍♀️,🧛🏼‍♀️,🧛🏽‍♀️,🧛🏾‍♀️,🧛🏿‍♀️	5.0
smileys	🧛	5.0	vampire	blood|dracula|fangs|halloween|scary|supernatural|teeth|undead	🧛🏻,🧛🏼,🧛🏽,🧛🏾,🧛🏿	5.0
smileys	🧛‍♂️	5.0	man vampire	blood|fangs|halloween|scary|supernatural|teeth|undead	🧛🏻‍♂️,🧛🏼‍♂️,🧛🏽‍♂️,🧛🏾‍♂️,🧛🏿‍♂️	5.0
smileys	🧟‍♀️	5.0	woman zombie	apocalypse|dead|halloween|horror|scary|undead|walking		
smileys	🧟	5.0	zombie	apocalypse|dead|halloween|horror|scary|undead|walking		
smileys	🧟‍♂️	5.0	man zombie	apocalypse|dead|halloween|horror|scary|undead|walking		
smileys	🧞‍♀️	5.0	woman genie	djinn|fantasy|jinn|lamp|myth|rub|wishes		
smileys	🧞	5.0	genie	djinn|fantasy|jinn|lamp|myth|rub|wishes		
smileys	🧞‍♂️	5.0	man genie	djinn|fantasy|jinn|lamp|myth|rub|wishes		
smileys	🧜‍♀️	5.0	mermaid	creature|fairytale|folklore|merwoman|ocean|sea|siren|trident	🧜🏻‍♀️,🧜🏼‍♀️,🧜🏽‍♀️,🧜🏾‍♀️,🧜🏿‍♀️	5.0
smileys	🧜	5.0	merperson	creature|fairytale|folklore|ocean|sea|siren|trident	🧜🏻,🧜🏼,🧜🏽,🧜🏾,🧜🏿	5.0
smileys	🧜‍♂️	5.0	merman	creature|fairytale|folklore|neptune|ocean|poseidon|sea|siren|trident|triton	🧜🏻‍♂️,🧜🏼‍♂️,🧜🏽‍♂️,🧜🏾‍♂️,🧜🏿‍♂️	5.0
smileys	🧚‍♀️	5.0	woman fairy	fairytale|fantasy|myth|person|pixie|tale|titania|wings	🧚🏻‍♀️,🧚🏼‍♀️,🧚🏽‍♀️,🧚🏾‍♀️,🧚🏿‍♀️	5.0
smileys	🧚	5.0	fairy	fairytale|fantasy|myth|person|pixie|tale|wings	🧚🏻,🧚🏼,🧚🏽,🧚🏾,🧚🏿	5.0
smileys	🧚‍♂️	5.0	man fairy	fairytale|fantasy|myth|oberon|person|pixie|puck|tale|wings	🧚🏻‍♂️,🧚🏼‍♂️,🧚🏽‍♂️,🧚🏾‍♂️,🧚🏿‍♂️	5.0
smileys	👼	0.6	baby angel	church|face|fairy|fairytale|fantasy|tale	👼🏻,👼🏼,👼🏽,👼🏾,👼🏿	1.0
smileys	🤰	3.0	pregnant woman		🤰🏻,🤰🏼,🤰🏽,🤰🏾,🤰🏿	3.0
smileys	🫄	14.0	pregnant person	belly|bloated|full|overeat|stuffed	🫄🏻,🫄🏼,🫄🏽,🫄🏾,🫄🏿	14.0
smileys	🫃	14.0	pregnant man	belly|bloated|full|overeat	🫃🏻,🫃🏼,🫃🏽,🫃🏾,🫃🏿	14.0
smileys	🤱	5.0	breast-feeding	baby|mom|mother|nursing|woman	🤱🏻,🤱🏼,🤱🏽,🤱🏾,🤱🏿	5.0
smileys	👩‍🍼	13.0	woman feeding baby	feed|mom|mother|nanny|newborn|nursing	👩🏻‍🍼,👩🏼‍🍼,👩🏽‍🍼,👩🏾‍🍼,👩🏿‍🍼	13.0
smileys	🧑‍🍼	13.0	person feeding baby	feed|nanny|newborn|nursing|parent	🧑🏻‍🍼,🧑🏼‍🍼,🧑🏽‍🍼,🧑🏾‍🍼,🧑🏿‍🍼	13.0
smileys	👨‍🍼	13.0	man feeding baby	dad|father|feed|nanny|newborn|nursing	👨🏻‍🍼,👨🏼‍🍼,👨🏽‍🍼,👨🏾‍🍼,👨🏿‍🍼	13.0
smileys	🙇‍♀️	4.0	woman bowing	apology|ask|beg|bow|favor|forgive|gesture|meditate|meditation|pity|regret|sorry	🙇🏻‍♀️,🙇🏼‍♀️,🙇🏽‍♀️,🙇🏾‍♀️,🙇🏿‍♀️	4.0
smileys	🙇	0.6	person bowing	apology|ask|beg|bow|favor|forgive|gesture|meditate|meditation|pity|regret|sorry	🙇🏻,🙇🏼,🙇🏽,🙇🏾,🙇🏿	1.0
smileys	🙇‍♂️	4.0	man bowing	apology|ask|beg|bow|favor|forgive|gesture|meditate|meditation|pity|regret|sorry	🙇🏻‍♂️,🙇🏼‍♂️,🙇🏽‍♂️,🙇🏾‍♂️,🙇🏿‍♂️	4.0
smileys	💁‍♀️	4.0	woman tipping hand	fetch|flick|flip|gossip|sarcasm|sarcastic|sassy|seriously|whatever	💁🏻‍♀️,💁🏼‍♀️,💁🏽‍♀️,💁🏾‍♀️,💁🏿‍♀️	4.0
smileys	💁	0.6	person tipping hand	fetch|flick|flip|gossip|sarcasm|sarcastic|sassy|seriously|whatever	💁🏻,💁🏼,💁🏽,💁🏾,💁🏿	1.0
smileys	💁‍♂️	4.0	man tipping hand	fetch|flick|flip|gossip|sarcasm|sarcastic|sassy|seriously|whatever	💁🏻‍♂️,💁🏼‍♂️,💁🏽‍♂️,💁🏾‍♂️,💁🏿‍♂️	4.0
smileys	🙅‍♀️	4.0	woman gesturing NO	forbidden|gesture|hand|not|prohibit	🙅🏻‍♀️,🙅🏼‍♀️,🙅🏽‍♀️,🙅🏾‍♀️,🙅🏿‍♀️	4.0
smileys	🙅	0.6	person gesturing NO	forbidden|gesture|hand|not|prohibit	🙅🏻,🙅🏼,🙅🏽,🙅🏾,🙅🏿	1.0
smileys	🙅‍♂️	4.0	man gesturing NO	forbidden|gesture|hand|not|prohibit	🙅🏻‍♂️,🙅🏼‍♂️,🙅🏽‍♂️,🙅🏾‍♂️,🙅🏿‍♂️	4.0
smileys	🙆‍♀️	4.0	woman gesturing OK	exercise|gesture|hand|omg	🙆🏻‍♀️,🙆🏼‍♀️,🙆🏽‍♀️,🙆🏾‍♀️,🙆🏿‍♀️	4.0
smileys	🙆	0.6	person gesturing OK	exercise|gesture|hand|omg	🙆🏻,🙆🏼,🙆🏽,🙆🏾,🙆🏿	1.0
smileys	🙆‍♂️	4.0	man gesturing OK	exercise|gesture|hand|omg	🙆🏻‍♂️,🙆🏼‍♂️,🙆🏽‍♂️,🙆🏾‍♂️,🙆🏿‍♂️	4.0
smileys	🙋‍♀️	4.0	woman raising hand	gesture|here|know|me|pick|question|raise	🙋🏻‍♀️,🙋🏼‍♀️,🙋🏽‍♀️,🙋🏾‍♀️,🙋🏿‍♀️	4.0
smileys	🙋	0.6	person raising hand	gesture|here|know|me|pick|question|raise	🙋🏻,🙋🏼,🙋🏽,🙋🏾,🙋🏿	1.0
smileys	🙋‍♂️	4.0	man raising hand	gesture|here|know|me|pick|question|raise	🙋🏻‍♂️,🙋🏼‍♂️,🙋🏽‍♂️,🙋🏾‍♂️,🙋🏿‍♂️	4.0
smileys	🧏‍♀️	12.0	deaf woman	accessibility|ear|gesture|hear	🧏🏻‍♀️,🧏🏼‍♀️,🧏🏽‍♀️,🧏🏾‍♀️,🧏🏿‍♀️	12.0
smileys	🧏	12.0	deaf person	accessibility|ear|gesture|hear	🧏🏻,🧏🏼,🧏🏽,🧏🏾,🧏🏿	12.0
smileys	🧏‍♂️	12.0	deaf man	accessibility|ear|gesture|hear	🧏🏻‍♂️,🧏🏼‍♂️,🧏🏽‍♂️,🧏🏾‍♂️,🧏🏿‍♂️	12.0
smileys	🤦‍♀️	4.0	woman facepalming	again|bewilder|disbelief|exasperation|facepalm|no|not|oh|omg|shock|smh	🤦🏻‍♀️,🤦🏼‍♀️,🤦🏽‍♀️,🤦🏾‍♀️,🤦🏿‍♀️	4.0
smileys	🤦	3.0	person facepalming	again|bewilder|disbelief|exasperation|facepalm|no|not|oh|omg|shock|smh	🤦🏻,🤦🏼,🤦🏽,🤦🏾,🤦🏿	3.0
smileys	🤦‍♂️	4.0	man facepalming	again|bewilder|disbelief|exasperation|facepalm|no|not|oh|omg|shock|smh	🤦🏻‍♂️,🤦🏼‍♂️,🤦🏽‍♂️,🤦🏾‍♂️,🤦🏿‍♂️	4.0
smileys	🤷‍♀️	4.0	woman shrugging	doubt|dunno|guess|idk|ignorance|indifference|knows|maybe|shrug|whatever|who	🤷🏻‍♀️,🤷🏼‍♀️,🤷🏽‍♀️,🤷🏾‍♀️,🤷🏿‍♀️	4.0
smileys	🤷	3.0	person shrugging	doubt|dunno|guess|idk|ignorance|indifference|knows|maybe|shrug|whatever|who	🤷🏻,🤷🏼,🤷🏽,🤷🏾,🤷🏿	3.0
smileys	🤷‍♂️	4.0	man shrugging	doubt|dunno|guess|idk|ignorance|indifference|knows|maybe|shrug|whatever|who	🤷🏻‍♂️,🤷🏼‍♂️,🤷🏽‍♂️,🤷🏾‍♂️,🤷🏿‍♂️	4.0
smileys	🙎‍♀️	4.0	woman pouting	disappointed|downtrodden|frown|grimace|scowl|sulk|upset|whine	🙎🏻‍♀️,🙎🏼‍♀️,🙎🏽‍♀️,🙎🏾‍♀️,🙎🏿‍♀️	4.0
smileys	🙎	0.6	person pouting	disappointed|downtrodden|frown|grimace|scowl|sulk|upset|whine	🙎🏻,🙎🏼,🙎🏽,🙎🏾,🙎🏿	1.0
smileys	🙎‍♂️	4.0	man pouting	disappointed|downtrodden|frown|grimace|scowl|sulk|upset|whine	🙎🏻‍♂️,🙎🏼‍♂️,🙎🏽‍♂️,🙎🏾‍♂️,🙎🏿‍♂️	4.0
smileys	🙍‍♀️	4.0	woman frowning	annoyed|disappointed|disgruntled|disturbed|frown|frustrated|gesture|irritated|upset	🙍🏻‍♀️,🙍🏼‍♀️,🙍🏽‍♀️,🙍🏾‍♀️,🙍🏿‍♀️	4.0
smileys	🙍	0.6	person frowning	annoyed|disappointed|disgruntled|disturbed|frown|frustrated|gesture|irritated|upset	🙍🏻,🙍🏼,🙍🏽,🙍🏾,🙍🏿	1.0
smileys	🙍‍♂️	4.0	man frowning	annoyed|disappointed|disgruntled|disturbed|frown|frustrated|gesture|irritated|upset	🙍🏻‍♂️,🙍🏼‍♂️,🙍🏽‍♂️,🙍🏾‍♂️,🙍🏿‍♂️	4.0
smileys	💇‍♀️	4.0	woman getting haircut	barber|beauty|chop|cosmetology|cut|groom|hair|parlor|person|shears|style	💇🏻‍♀️,💇🏼‍♀️,💇🏽‍♀️,💇🏾‍♀️,💇🏿‍♀️	4.0
smileys	💇	0.6	person getting haircut	barber|beauty|chop|cosmetology|cut|groom|hair|parlor|shears|style	💇🏻,💇🏼,💇🏽,💇🏾,💇🏿	1.0
smileys	💇‍♂️	4.0	man getting haircut	barber|beauty|chop|cosmetology|cut|groom|hair|parlor|person|shears|style	💇🏻‍♂️,💇🏼‍♂️,💇🏽‍♂️,💇🏾‍♂️,💇🏿‍♂️	4.0
smileys	💆‍♀️	4.0	woman getting massage	face|headache|relax|relaxing|salon|soothe|spa|tension|therapy|treatment	💆🏻‍♀️,💆🏼‍♀️,💆🏽‍♀️,💆🏾‍♀️,💆🏿‍♀️	4.0
smileys	💆	0.6	person getting massage	face|headache|relax|relaxing|salon|soothe|spa|tension|therapy|treatment	💆🏻,💆🏼,💆🏽,💆🏾,💆🏿	1.0
smileys	💆‍♂️	4.0	man getting massage	face|headache|relax|relaxing|salon|soothe|spa|tension|therapy|treatment	💆🏻‍♂️,💆🏼‍♂️,💆🏽‍♂️,💆🏾‍♂️,💆🏿‍♂️	4.0
smileys	🧖‍♀️	5.0	woman in steamy room	day|luxurious|pamper|relax|sauna|spa|steam|steambath|unwind	🧖🏻‍♀️,🧖🏼‍♀️,🧖🏽‍♀️,🧖🏾‍♀️,🧖🏿‍♀️	5.0
smileys	🧖	5.0	person in steamy room	day|luxurious|pamper|relax|sauna|spa|steam|steambath|unwind	🧖🏻,🧖🏼,🧖🏽,🧖🏾,🧖🏿	5.0
smileys	🧖‍♂️	5.0	man in steamy room	day|luxurious|pamper|relax|sauna|spa|steam|steambath|unwind	🧖🏻‍♂️,🧖🏼‍♂️,🧖🏽‍♂️,🧖🏾‍♂️,🧖🏿‍♂️	5.0
smileys	💅	0.6	nail polish	bored|care|cosmetics|done|makeup|manicure|whatever	💅🏻,💅🏼,💅🏽,💅🏾,💅🏿	1.0
smileys	🤳	3.0	selfie	camera|phone	🤳🏻,🤳🏼,🤳🏽,🤳🏾,🤳🏿	3.0
smileys	💃	0.6	woman dancing	dance|dancer|elegant|festive|flair|flamenco|groove|let’s|salsa|tango	💃🏻,💃🏼,💃🏽,💃🏾,💃🏿	1.0
smileys	🕺	3.0	man dancing	dance|dancer|elegant|festive|flair|flamenco|groove|let’s|salsa|tango	🕺🏻,🕺🏼,🕺🏽,🕺🏾,🕺🏿	3.0
smileys	🧑‍🩰	17.0	ballet dancer		🧑🏻‍🩰,🧑🏼‍🩰,🧑🏽‍🩰,🧑🏾‍🩰,🧑🏿‍🩰	17.0
smileys	👯‍♀️	4.0	women with bunny ears	bestie|bff|counterpart|dancer|double|ear|identical|pair|party|partying|people|soulmate|twin|twinsies	👯🏻‍♀️,👯🏼‍♀️,👯🏽‍♀️,👯🏾‍♀️,👯🏿‍♀️,👩🏻‍🐰‍👩🏼,👩🏻‍🐰‍👩🏽,👩🏻‍🐰‍👩🏾,👩🏻‍🐰‍👩🏿,👩🏼‍🐰‍👩🏻,👩🏼‍🐰‍👩🏽,👩🏼‍🐰‍👩🏾,👩🏼‍🐰‍👩🏿,👩🏽‍🐰‍👩🏻,👩🏽‍🐰‍👩🏼,👩🏽‍🐰‍👩🏾,👩🏽‍🐰‍👩🏿,👩🏾‍🐰‍👩🏻,👩🏾‍🐰‍👩🏼,👩🏾‍🐰‍👩🏽,👩🏾‍🐰‍👩🏿,👩🏿‍🐰‍👩🏻,👩🏿‍🐰‍👩🏼,👩🏿‍🐰‍👩🏽,👩🏿‍🐰‍👩🏾	17.0
smileys	👯	0.6	people with bunny ears	bestie|bff|counterpart|dancer|double|ear|identical|pair|party|partying|soulmate|twin|twinsies	👯🏻,👯🏼,👯🏽,👯🏾,👯🏿,🧑🏻‍🐰‍🧑🏼,🧑🏻‍🐰‍🧑🏽,🧑🏻‍🐰‍🧑🏾,🧑🏻‍🐰‍🧑🏿,🧑🏼‍🐰‍🧑🏻,🧑🏼‍🐰‍🧑🏽,🧑🏼‍🐰‍🧑🏾,🧑🏼‍🐰‍🧑🏿,🧑🏽‍🐰‍🧑🏻,🧑🏽‍🐰‍🧑🏼,🧑🏽‍🐰‍🧑🏾,🧑🏽‍🐰‍🧑🏿,🧑🏾‍🐰‍🧑🏻,🧑🏾‍🐰‍🧑🏼,🧑🏾‍🐰‍🧑🏽,🧑🏾‍🐰‍🧑🏿,🧑🏿‍🐰‍🧑🏻,🧑🏿‍🐰‍🧑🏼,🧑🏿‍🐰‍🧑🏽,🧑🏿‍🐰‍🧑🏾	17.0
smileys	👯‍♂️	4.0	men with bunny ears	bestie|bff|counterpart|dancer|double|ear|identical|pair|party|partying|people|soulmate|twin|twinsies	👯🏻‍♂️,👯🏼‍♂️,👯🏽‍♂️,👯🏾‍♂️,👯🏿‍♂️,👨🏻‍🐰‍👨🏼,👨🏻‍🐰‍👨🏽,👨🏻‍🐰‍👨🏾,👨🏻‍🐰‍👨🏿,👨🏼‍🐰‍👨🏻,👨🏼‍🐰‍👨🏽,👨🏼‍🐰‍👨🏾,👨🏼‍🐰‍👨🏿,👨🏽‍🐰‍👨🏻,👨🏽‍🐰‍👨🏼,👨🏽‍🐰‍👨🏾,👨🏽‍🐰‍👨🏿,👨🏾‍🐰‍👨🏻,👨🏾‍🐰‍👨🏼,👨🏾‍🐰‍👨🏽,👨🏾‍🐰‍👨🏿,👨🏿‍🐰‍👨🏻,👨🏿‍🐰‍👨🏼,👨🏿‍🐰‍👨🏽,👨🏿‍🐰‍👨🏾	17.0
smileys	🕴️	0.7	person in suit levitating	business	🕴🏻,🕴🏼,🕴🏽,🕴🏾,🕴🏿	4.0
smileys	👩‍🦽	12.0	woman in manual wheelchair	accessibility	👩🏻‍🦽,👩🏼‍🦽,👩🏽‍🦽,👩🏾‍🦽,👩🏿‍🦽	12.0
smileys	🧑‍🦽	12.1	person in manual wheelchair	accessibility	🧑🏻‍🦽,🧑🏼‍🦽,🧑🏽‍🦽,🧑🏾‍🦽,🧑🏿‍🦽	12.1
smileys	👨‍🦽	12.0	man in manual wheelchair	accessibility	👨🏻‍🦽,👨🏼‍🦽,👨🏽‍🦽,👨🏾‍🦽,👨🏿‍🦽	12.0
smileys	👩‍🦽‍➡️	15.1	woman in manual wheelchair facing right	accessibility	👩🏻‍🦽‍➡️,👩🏼‍🦽‍➡️,👩🏽‍🦽‍➡️,👩🏾‍🦽‍➡️,👩🏿‍🦽‍➡️	15.1
smileys	🧑‍🦽‍➡️	15.1	person in manual wheelchair facing right	accessibility	🧑🏻‍🦽‍➡️,🧑🏼‍🦽‍➡️,🧑🏽‍🦽‍➡️,🧑🏾‍🦽‍➡️,🧑🏿‍🦽‍➡️	15.1
smileys	👨‍🦽‍➡️	15.1	man in manual wheelchair facing right	accessibility	👨🏻‍🦽‍➡️,👨🏼‍🦽‍➡️,👨🏽‍🦽‍➡️,👨🏾‍🦽‍➡️,👨🏿‍🦽‍➡️	15.1
smileys	👩‍🦼	12.0	woman in motorized wheelchair	accessibility	👩🏻‍🦼,👩🏼‍🦼,👩🏽‍🦼,👩🏾‍🦼,👩🏿‍🦼	12.0
smileys	🧑‍🦼	12.1	person in motorized wheelchair	accessibility	🧑🏻‍🦼,🧑🏼‍🦼,🧑🏽‍🦼,🧑🏾‍🦼,🧑🏿‍🦼	12.1
smileys	👨‍🦼	12.0	man in motorized wheelchair	accessibility	👨🏻‍🦼,👨🏼‍🦼,👨🏽‍🦼,👨🏾‍🦼,👨🏿‍🦼	12.0
smileys	👩‍🦼‍➡️	15.1	woman in motorized wheelchair facing right	accessibility	👩🏻‍🦼‍➡️,👩🏼‍🦼‍➡️,👩🏽‍🦼‍➡️,👩🏾‍🦼‍➡️,👩🏿‍🦼‍➡️	15.1
smileys	🧑‍🦼‍➡️	15.1	person in motorized wheelchair facing right	accessibility	🧑🏻‍🦼‍➡️,🧑🏼‍🦼‍➡️,🧑🏽‍🦼‍➡️,🧑🏾‍🦼‍➡️,🧑🏿‍🦼‍➡️	15.1
smileys	👨‍🦼‍➡️	15.1	man in motorized wheelchair facing right	accessibility	👨🏻‍🦼‍➡️,👨🏼‍🦼‍➡️,👨🏽‍🦼‍➡️,👨🏾‍🦼‍➡️,👨🏿‍🦼‍➡️	15.1
smileys	🚶‍♀️	4.0	woman walking	amble|gait|hike|man|pace|pedestrian|stride|stroll|walk	🚶🏻‍♀️,🚶🏼‍♀️,🚶🏽‍♀️,🚶🏾‍♀️,🚶🏿‍♀️	4.0
smileys	🚶	0.6	person walking	amble|gait|hike|man|pace|pedestrian|stride|stroll|walk	🚶🏻,🚶🏼,🚶🏽,🚶🏾,🚶🏿	1.0
smileys	🚶‍♂️	4.0	man walking	amble|gait|hike|pace|pedestrian|stride|stroll|walk	🚶🏻‍♂️,🚶🏼‍♂️,🚶🏽‍♂️,🚶🏾‍♂️,🚶🏿‍♂️	4.0
smileys	🚶‍♀️‍➡️	15.1	woman walking facing right	amble|gait|hike|man|pace|pedestrian|stride|stroll|walk	🚶🏻‍♀️‍➡️,🚶🏼‍♀️‍➡️,🚶🏽‍♀️‍➡️,🚶🏾‍♀️‍➡️,🚶🏿‍♀️‍➡️	15.1
smileys	🚶‍➡️	15.1	person walking facing right	amble|gait|hike|man|pace|pedestrian|stride|stroll|walk	🚶🏻‍➡️,🚶🏼‍➡️,🚶🏽‍➡️,🚶🏾‍➡️,🚶🏿‍➡️	15.1
smileys	🚶‍♂️‍➡️	15.1	man walking facing right	amble|gait|hike|pace|pedestrian|stride|stroll|walk	🚶🏻‍♂️‍➡️,🚶🏼‍♂️‍➡️,🚶🏽‍♂️‍➡️,🚶🏾‍♂️‍➡️,🚶🏿‍♂️‍➡️	15.1
smileys	👩‍🦯	12.0	woman with white cane	accessibility|blind|probing	👩🏻‍🦯,👩🏼‍🦯,👩🏽‍🦯,👩🏾‍🦯,👩🏿‍🦯	12.0
smileys	🧑‍🦯	12.1	person with white cane	accessibility|blind|probing	🧑🏻‍🦯,🧑🏼‍🦯,🧑🏽‍🦯,🧑🏾‍🦯,🧑🏿‍🦯	12.1
smileys	👨‍🦯	12.0	man with white cane	accessibility|blind|probing	👨🏻‍🦯,👨🏼‍🦯,👨🏽‍🦯,👨🏾‍🦯,👨🏿‍🦯	12.0
smileys	👩‍🦯‍➡️	15.1	woman with white cane facing right	accessibility|blind|probing	👩🏻‍🦯‍➡️,👩🏼‍🦯‍➡️,👩🏽‍🦯‍➡️,👩🏾‍🦯‍➡️,👩🏿‍🦯‍➡️	15.1
smileys	🧑‍🦯‍➡️	15.1	person with white cane facing right	accessibility|blind|probing	🧑🏻‍🦯‍➡️,🧑🏼‍🦯‍➡️,🧑🏽‍🦯‍➡️,🧑🏾‍🦯‍➡️,🧑🏿‍🦯‍➡️	15.1
smileys	👨‍🦯‍➡️	15.1	man with white cane facing right	accessibility|blind|probing	👨🏻‍🦯‍➡️,👨🏼‍🦯‍➡️,👨🏽‍🦯‍➡️,👨🏾‍🦯‍➡️,👨🏿‍🦯‍➡️	15.1
smileys	🧎‍♀️	12.0	woman kneeling	kneel|knees	🧎🏻‍♀️,🧎🏼‍♀️,🧎🏽‍♀️,🧎🏾‍♀️,🧎🏿‍♀️	12.0
smileys	🧎	12.0	person kneeling	kneel|knees	🧎🏻,🧎🏼,🧎🏽,🧎🏾,🧎🏿	12.0
smileys	🧎‍♂️	12.0	man kneeling	kneel|knees	🧎🏻‍♂️,🧎🏼‍♂️,🧎🏽‍♂️,🧎🏾‍♂️,🧎🏿‍♂️	12.0
smileys	🏃‍♀️	4.0	woman running	fast|hurry|marathon|move|quick|race|racing|run|rush|speed	🏃🏻‍♀️,🏃🏼‍♀️,🏃🏽‍♀️,🏃🏾‍♀️,🏃🏿‍♀️	4.0
smileys	🏃	0.6	person running	fast|hurry|marathon|move|quick|race|racing|run|rush|speed	🏃🏻,🏃🏼,🏃🏽,🏃🏾,🏃🏿	1.0
smileys	🏃‍♂️	4.0	man running	fast|hurry|marathon|move|quick|race|racing|run|rush|speed	🏃🏻‍♂️,🏃🏼‍♂️,🏃🏽‍♂️,🏃🏾‍♂️,🏃🏿‍♂️	4.0
smileys	🏃‍♀️‍➡️	15.1	woman running facing right	fast|hurry|marathon|move|quick|race|racing|run|rush|speed	🏃🏻‍♀️‍➡️,🏃🏼‍♀️‍➡️,🏃🏽‍♀️‍➡️,🏃🏾‍♀️‍➡️,🏃🏿‍♀️‍➡️	15.1
smileys	🏃‍➡️	15.1	person running facing right	fast|hurry|marathon|move|quick|race|racing|run|rush|speed	🏃🏻‍➡️,🏃🏼‍➡️,🏃🏽‍➡️,🏃🏾‍➡️,🏃🏿‍➡️	15.1
smileys	🏃‍♂️‍➡️	15.1	man running facing right	fast|hurry|marathon|move|quick|race|racing|run|rush|speed	🏃🏻‍♂️‍➡️,🏃🏼‍♂️‍➡️,🏃🏽‍♂️‍➡️,🏃🏾‍♂️‍➡️,🏃🏿‍♂️‍➡️	15.1
smileys	🧎‍♀️‍➡️	15.1	woman kneeling facing right	kneel|knees	🧎🏻‍♀️‍➡️,🧎🏼‍♀️‍➡️,🧎🏽‍♀️‍➡️,🧎🏾‍♀️‍➡️,🧎🏿‍♀️‍➡️	15.1
smileys	🧎‍➡️	15.1	person kneeling facing right	kneel|knees	🧎🏻‍➡️,🧎🏼‍➡️,🧎🏽‍➡️,🧎🏾‍➡️,🧎🏿‍➡️	15.1
smileys	🧎‍♂️‍➡️	15.1	man kneeling facing right	kneel|knees	🧎🏻‍♂️‍➡️,🧎🏼‍♂️‍➡️,🧎🏽‍♂️‍➡️,🧎🏾‍♂️‍➡️,🧎🏿‍♂️‍➡️	15.1
smileys	🧍‍♀️	12.0	woman standing	stand	🧍🏻‍♀️,🧍🏼‍♀️,🧍🏽‍♀️,🧍🏾‍♀️,🧍🏿‍♀️	12.0
smileys	🧍	12.0	person standing	stand	🧍🏻,🧍🏼,🧍🏽,🧍🏾,🧍🏿	12.0
smileys	🧍‍♂️	12.0	man standing	stand	🧍🏻‍♂️,🧍🏼‍♂️,🧍🏽‍♂️,🧍🏾‍♂️,🧍🏿‍♂️	12.0
smileys	👫	0.6	woman and man holding hands	bae|bestie|bff|couple|dating|flirt|friends|hand|hold|twins	👫🏻,👩🏻‍🤝‍👨🏼,👩🏻‍🤝‍👨🏽,👩🏻‍🤝‍👨🏾,👩🏻‍🤝‍👨🏿,👩🏼‍🤝‍👨🏻,👫🏼,👩🏼‍🤝‍👨🏽,👩🏼‍🤝‍👨🏾,👩🏼‍🤝‍👨🏿,👩🏽‍🤝‍👨🏻,👩🏽‍🤝‍👨🏼,👫🏽,👩🏽‍🤝‍👨🏾,👩🏽‍🤝‍👨🏿,👩🏾‍🤝‍👨🏻,👩🏾‍🤝‍👨🏼,👩🏾‍🤝‍👨🏽,👫🏾,👩🏾‍🤝‍👨🏿,👩🏿‍🤝‍👨🏻,👩🏿‍🤝‍👨🏼,👩🏿‍🤝‍👨🏽,👩🏿‍🤝‍👨🏾,👫🏿	12.0
smileys	👭	1.0	women holding hands	bae|bestie|bff|couple|dating|flirt|friends|girls|hand|hold|sisters|twins	👭🏻,👩🏻‍🤝‍👩🏼,👩🏻‍🤝‍👩🏽,👩🏻‍🤝‍👩🏾,👩🏻‍🤝‍👩🏿,👩🏼‍🤝‍👩🏻,👭🏼,👩🏼‍🤝‍👩🏽,👩🏼‍🤝‍👩🏾,👩🏼‍🤝‍👩🏿,👩🏽‍🤝‍👩🏻,👩🏽‍🤝‍👩🏼,👭🏽,👩🏽‍🤝‍👩🏾,👩🏽‍🤝‍👩🏿,👩🏾‍🤝‍👩🏻,👩🏾‍🤝‍👩🏼,👩🏾‍🤝‍👩🏽,👭🏾,👩🏾‍🤝‍👩🏿,👩🏿‍🤝‍👩🏻,👩🏿‍🤝‍👩🏼,👩🏿‍🤝‍👩🏽,👩🏿‍🤝‍👩🏾,👭🏿	12.0,12.1,12.1,12.1,12.1,12.0,12.0,12.1,12.1,12.1,12.0,12.0,12.0,12.1,12.1,12.0,12.0,12.0,12.0,12.1,12.0,12.0,12.0,12.0,12.0
smileys	👬	1.0	men holding hands	bae|bestie|bff|boys|brothers|couple|dating|flirt|friends|hand|hold|twins	👬🏻,👨🏻‍🤝‍👨🏼,👨🏻‍🤝‍👨🏽,👨🏻‍🤝‍👨🏾,👨🏻‍🤝‍👨🏿,👨🏼‍🤝‍👨🏻,👬🏼,👨🏼‍🤝‍👨🏽,👨🏼‍🤝‍👨🏾,👨🏼‍🤝‍👨🏿,👨🏽‍🤝‍👨🏻,👨🏽‍🤝‍👨🏼,👬🏽,👨🏽‍🤝‍👨🏾,👨🏽‍🤝‍👨🏿,👨🏾‍🤝‍👨🏻,👨🏾‍🤝‍👨🏼,👨🏾‍🤝‍👨🏽,👬🏾,👨🏾‍🤝‍👨🏿,👨🏿‍🤝‍👨🏻,👨🏿‍🤝‍👨🏼,👨🏿‍🤝‍👨🏽,👨🏿‍🤝‍👨🏾,👬🏿	12.0,12.1,12.1,12.1,12.1,12.0,12.0,12.1,12.1,12.1,12.0,12.0,12.0,12.1,12.1,12.0,12.0,12.0,12.0,12.1,12.0,12.0,12.0,12.0,12.0
smileys	👩‍❤️‍👨	2.0	couple with heart: woman, man	anniversary|babe|bae|dating|kiss|love|person|relationship|romance|together|you	👩🏻‍❤️‍👨🏻,👩🏻‍❤️‍👨🏼,👩🏻‍❤️‍👨🏽,👩🏻‍❤️‍👨🏾,👩🏻‍❤️‍👨🏿,👩🏼‍❤️‍👨🏻,👩🏼‍❤️‍👨🏼,👩🏼‍❤️‍👨🏽,👩🏼‍❤️‍👨🏾,👩🏼‍❤️‍👨🏿,👩🏽‍❤️‍👨🏻,👩🏽‍❤️‍👨🏼,👩🏽‍❤️‍👨🏽,👩🏽‍❤️‍👨🏾,👩🏽‍❤️‍👨🏿,👩🏾‍❤️‍👨🏻,👩🏾‍❤️‍👨🏼,👩🏾‍❤️‍👨🏽,👩🏾‍❤️‍👨🏾,👩🏾‍❤️‍👨🏿,👩🏿‍❤️‍👨🏻,👩🏿‍❤️‍👨🏼,👩🏿‍❤️‍👨🏽,👩🏿‍❤️‍👨🏾,👩🏿‍❤️‍👨🏿	13.1
smileys	👩‍❤️‍👩	2.0	couple with heart: woman, woman	anniversary|babe|bae|dating|kiss|love|person|relationship|romance|together|you	👩🏻‍❤️‍👩🏻,👩🏻‍❤️‍👩🏼,👩🏻‍❤️‍👩🏽,👩🏻‍❤️‍👩🏾,👩🏻‍❤️‍👩🏿,👩🏼‍❤️‍👩🏻,👩🏼‍❤️‍👩🏼,👩🏼‍❤️‍👩🏽,👩🏼‍❤️‍👩🏾,👩🏼‍❤️‍👩🏿,👩🏽‍❤️‍👩🏻,👩🏽‍❤️‍👩🏼,👩🏽‍❤️‍👩🏽,👩🏽‍❤️‍👩🏾,👩🏽‍❤️‍👩🏿,👩🏾‍❤️‍👩🏻,👩🏾‍❤️‍👩🏼,👩🏾‍❤️‍👩🏽,👩🏾‍❤️‍👩🏾,👩🏾‍❤️‍👩🏿,👩🏿‍❤️‍👩🏻,👩🏿‍❤️‍👩🏼,👩🏿‍❤️‍👩🏽,👩🏿‍❤️‍👩🏾,👩🏿‍❤️‍👩🏿	13.1
smileys	💑	0.6	couple with heart	anniversary|babe|bae|dating|kiss|love|person|relationship|romance|together|you	💑🏻,💑🏼,💑🏽,💑🏾,💑🏿,🧑🏻‍❤️‍🧑🏼,🧑🏻‍❤️‍🧑🏽,🧑🏻‍❤️‍🧑🏾,🧑🏻‍❤️‍🧑🏿,🧑🏼‍❤️‍🧑🏻,🧑🏼‍❤️‍🧑🏽,🧑🏼‍❤️‍🧑🏾,🧑🏼‍❤️‍🧑🏿,🧑🏽‍❤️‍🧑🏻,🧑🏽‍❤️‍🧑🏼,🧑🏽‍❤️‍🧑🏾,🧑🏽‍❤️‍🧑🏿,🧑🏾‍❤️‍🧑🏻,🧑🏾‍❤️‍🧑🏼,🧑🏾‍❤️‍🧑🏽,🧑🏾‍❤️‍🧑🏿,🧑🏿‍❤️‍🧑🏻,🧑🏿‍❤️‍🧑🏼,🧑🏿‍❤️‍🧑🏽,🧑🏿‍❤️‍🧑🏾	13.1
smileys	👨‍❤️‍👨	2.0	couple with heart: man, man	anniversary|babe|bae|dating|kiss|love|person|relationship|romance|together|you	👨🏻‍❤️‍👨🏻,👨🏻‍❤️‍👨🏼,👨🏻‍❤️‍👨🏽,👨🏻‍❤️‍👨🏾,👨🏻‍❤️‍👨🏿,👨🏼‍❤️‍👨🏻,👨🏼‍❤️‍👨🏼,👨🏼‍❤️‍👨🏽,👨🏼‍❤️‍👨🏾,👨🏼‍❤️‍👨🏿,👨🏽‍❤️‍👨🏻,👨🏽‍❤️‍👨🏼,👨🏽‍❤️‍👨🏽,👨🏽‍❤️‍👨🏾,👨🏽‍❤️‍👨🏿,👨🏾‍❤️‍👨🏻,👨🏾‍❤️‍👨🏼,👨🏾‍❤️‍👨🏽,👨🏾‍❤️‍👨🏾,👨🏾‍❤️‍👨🏿,👨🏿‍❤️‍👨🏻,👨🏿‍❤️‍👨🏼,👨🏿‍❤️‍👨🏽,👨🏿‍❤️‍👨🏾,👨🏿‍❤️‍👨🏿	13.1
smileys	👩‍❤️‍💋‍👨	2.0	kiss: woman, man	anniversary|babe|bae|couple|date|dating|heart|love|mwah|person|romance|together|xoxo	👩🏻‍❤️‍💋‍👨🏻,👩🏻‍❤️‍💋‍👨🏼,👩🏻‍❤️‍💋‍👨🏽,👩🏻‍❤️‍💋‍👨🏾,👩🏻‍❤️‍💋‍👨🏿,👩🏼‍❤️‍💋‍👨🏻,👩🏼‍❤️‍💋‍👨🏼,👩🏼‍❤️‍💋‍👨🏽,👩🏼‍❤️‍💋‍👨🏾,👩🏼‍❤️‍💋‍👨🏿,👩🏽‍❤️‍💋‍👨🏻,👩🏽‍❤️‍💋‍👨🏼,👩🏽‍❤️‍💋‍👨🏽,👩🏽‍❤️‍💋‍👨🏾,👩🏽‍❤️‍💋‍👨🏿,👩🏾‍❤️‍💋‍👨🏻,👩🏾‍❤️‍💋‍👨🏼,👩🏾‍❤️‍💋‍👨🏽,👩🏾‍❤️‍💋‍👨🏾,👩🏾‍❤️‍💋‍👨🏿,👩🏿‍❤️‍💋‍👨🏻,👩🏿‍❤️‍💋‍👨🏼,👩🏿‍❤️‍💋‍👨🏽,👩🏿‍❤️‍💋‍👨🏾,👩🏿‍❤️‍💋‍👨🏿	13.1
smileys	👩‍❤️‍💋‍👩	2.0	kiss: woman, woman	anniversary|babe|bae|couple|date|dating|heart|love|mwah|person|romance|together|xoxo	👩🏻‍❤️‍💋‍👩🏻,👩🏻‍❤️‍💋‍👩🏼,👩🏻‍❤️‍💋‍👩🏽,👩🏻‍❤️‍💋‍👩🏾,👩🏻‍❤️‍💋‍👩🏿,👩🏼‍❤️‍💋‍👩🏻,👩🏼‍❤️‍💋‍👩🏼,👩🏼‍❤️‍💋‍👩🏽,👩🏼‍❤️‍💋‍👩🏾,👩🏼‍❤️‍💋‍👩🏿,👩🏽‍❤️‍💋‍👩🏻,👩🏽‍❤️‍💋‍👩🏼,👩🏽‍❤️‍💋‍👩🏽,👩🏽‍❤️‍💋‍👩🏾,👩🏽‍❤️‍💋‍👩🏿,👩🏾‍❤️‍💋‍👩🏻,👩🏾‍❤️‍💋‍👩🏼,👩🏾‍❤️‍💋‍👩🏽,👩🏾‍❤️‍💋‍👩🏾,👩🏾‍❤️‍💋‍👩🏿,👩🏿‍❤️‍💋‍👩🏻,👩🏿‍❤️‍💋‍👩🏼,👩🏿‍❤️‍💋‍👩🏽,👩🏿‍❤️‍💋‍👩🏾,👩🏿‍❤️‍💋‍👩🏿	13.1
smileys	💏	0.6	kiss	anniversary|babe|bae|couple|date|dating|heart|love|mwah|person|romance|together|xoxo	💏🏻,💏🏼,💏🏽,💏🏾,💏🏿,🧑🏻‍❤️‍💋‍🧑🏼,🧑🏻‍❤️‍💋‍🧑🏽,🧑🏻‍❤️‍💋‍🧑🏾,🧑🏻‍❤️‍💋‍🧑🏿,🧑🏼‍❤️‍💋‍🧑🏻,🧑🏼‍❤️‍💋‍🧑🏽,🧑🏼‍❤️‍💋‍🧑🏾,🧑🏼‍❤️‍💋‍🧑🏿,🧑🏽‍❤️‍💋‍🧑🏻,🧑🏽‍❤️‍💋‍🧑🏼,🧑🏽‍❤️‍💋‍🧑🏾,🧑🏽‍❤️‍💋‍🧑🏿,🧑🏾‍❤️‍💋‍🧑🏻,🧑🏾‍❤️‍💋‍🧑🏼,🧑🏾‍❤️‍💋‍🧑🏽,🧑🏾‍❤️‍💋‍🧑🏿,🧑🏿‍❤️‍💋‍🧑🏻,🧑🏿‍❤️‍💋‍🧑🏼,🧑🏿‍❤️‍💋‍🧑🏽,🧑🏿‍❤️‍💋‍🧑🏾	13.1
smileys	👨‍❤️‍💋‍👨	2.0	kiss: man, man	anniversary|babe|bae|couple|date|dating|heart|love|mwah|person|romance|together|xoxo	👨🏻‍❤️‍💋‍👨🏻,👨🏻‍❤️‍💋‍👨🏼,👨🏻‍❤️‍💋‍👨🏽,👨🏻‍❤️‍💋‍👨🏾,👨🏻‍❤️‍💋‍👨🏿,👨🏼‍❤️‍💋‍👨🏻,👨🏼‍❤️‍💋‍👨🏼,👨🏼‍❤️‍💋‍👨🏽,👨🏼‍❤️‍💋‍👨🏾,👨🏼‍❤️‍💋‍👨🏿,👨🏽‍❤️‍💋‍👨🏻,👨🏽‍❤️‍💋‍👨🏼,👨🏽‍❤️‍💋‍👨🏽,👨🏽‍❤️‍💋‍👨🏾,👨🏽‍❤️‍💋‍👨🏿,👨🏾‍❤️‍💋‍👨🏻,👨🏾‍❤️‍💋‍👨🏼,👨🏾‍❤️‍💋‍👨🏽,👨🏾‍❤️‍💋‍👨🏾,👨🏾‍❤️‍💋‍👨🏿,👨🏿‍❤️‍💋‍👨🏻,👨🏿‍❤️‍💋‍👨🏼,👨🏿‍❤️‍💋‍👨🏽,👨🏿‍❤️‍💋‍👨🏾,👨🏿‍❤️‍💋‍👨🏿	13.1
smileys	🪢	13.0	knot	cord|rope|tangled|tie|twine|twist		
smileys	🧶	11.0	yarn	ball|crochet|knit		
smileys	🧵	11.0	thread	needle|sewing|spool|string		
smileys	🪡	13.0	sewing needle	embroidery|sew|stitches|sutures|tailoring|thread		
smileys	🧥	5.0	coat	brr|bundle|cold|jacket|up		
smileys	🥼	11.0	lab coat	clothes|doctor|dr|experiment|jacket|scientist|white		
smileys	🦺	12.0	safety vest	emergency		
smileys	👚	0.6	woman’s clothes	blouse|clothing|collar|dress|dressed|lady|shirt|shopping		
smileys	👕	0.6	t-shirt	blue|casual|clothes|clothing|collar|dressed|shopping|tshirt|weekend		
smileys	👖	0.6	jeans	blue|casual|clothes|clothing|denim|dressed|pants|shopping|trousers|weekend		
smileys	🩲	12.0	briefs	bathing|one-piece|suit|swimsuit|underwear		
smileys	🩳	12.0	shorts	bathing|pants|suit|swimsuit|underwear		
smileys	👔	0.6	necktie	clothing|employed|serious|shirt|tie		
smileys	👗	0.6	dress	clothes|clothing|dressed|fancy|shopping		
smileys	👙	0.6	bikini	bathing|beach|clothing|pool|suit|swim		
smileys	🩱	12.0	one-piece swimsuit	bathing|suit		
smileys	👘	0.6	kimono	clothing|comfortable		
smileys	🥻	12.0	sari	clothing|dress		
smileys	🩴	13.0	thong sandal	beach|flip|flop|sandals|shoe|thongs|zōri		
smileys	🥿	11.0	flat shoe	ballet|comfy|flats|slip-on|slipper		
smileys	👠	0.6	high-heeled shoe	clothes|clothing|dress|fashion|heel|heels|shoes|shopping|stiletto|woman		
smileys	👡	0.6	woman’s sandal	clothing|shoe		
smileys	👢	0.6	woman’s boot	clothes|clothing|dress|shoe|shoes|shopping		
smileys	👞	0.6	man’s shoe	brown|clothes|clothing|feet|foot|kick|shoes|shopping		
smileys	👟	0.6	running shoe	athletic|clothes|clothing|fast|kick|shoes|shopping|sneaker|tennis		
smileys	🥾	11.0	hiking boot	backpacking|brown|camping|outdoors|shoe		
smileys	🧦	5.0	socks	stocking		
smileys	🧤	5.0	gloves	hand		
smileys	🧣	5.0	scarf	bundle|cold|neck|up		
smileys	🎩	0.6	top hat	clothes|clothing|fancy|formal|magic|tophat		
smileys	🧢	5.0	billed cap	baseball|bent|dad|hat		
smileys	👒	0.6	woman’s hat	clothes|clothing|garden|hats|party		
smileys	🎓	0.6	graduation cap	celebration|clothing|education|hat|scholar		
smileys	⛑️	0.7	rescue worker’s helmet	aid|cross|face|hat		
smileys	🪖	13.0	military helmet	army|soldier|war|warrior		
smileys	👑	0.6	crown	clothing|family|king|medieval|queen|royal|royalty|win		
smileys	💍	0.6	ring	diamond|engaged|engagement|married|romance|shiny|sparkling|wedding		
smileys	👝	0.6	clutch bag	clothes|clothing|dress|handbag|pouch|purse		
smileys	👛	0.6	purse	clothes|clothing|coin|dress|fancy|handbag|shopping		
smileys	👜	0.6	handbag	bag|clothes|clothing|dress|lady|purse|shopping		
smileys	💼	0.6	briefcase	office		
smileys	🎒	0.6	backpack	backpacking|bag|bookbag|education|rucksack|satchel|school		
smileys	🧳	11.0	luggage	bag|packing|roller|suitcase|travel		
smileys	👓	0.6	glasses	clothing|eye|eyeglasses|eyewear		
smileys	🕶️	0.7	sunglasses	dark|eye|eyewear|glasses		
smileys	🥽	11.0	goggles	dive|eye|protection|scuba|swimming|welding		
smileys	🌂	0.6	closed umbrella	clothing|rain		
animals	🐶	0.6	dog face	adorbs|animal|pet|puppies|puppy		
animals	🐱	0.6	cat face	animal|kitten|kitty|pet		
animals	🐭	0.6	mouse face	animal		
animals	🐹	0.6	hamster	animal|face|pet		
animals	🐰	0.6	rabbit face	animal|bunny|pet		
animals	🦊	3.0	fox	animal|face		
animals	🐻	0.6	bear	animal|face|grizzly|growl|honey		
animals	🐼	0.6	panda	animal|bamboo|face		
animals	🐻‍❄️	13.0	polar bear	animal|arctic|white		
animals	🐨	0.6	koala	animal|australia|bear|down|face|marsupial|under		
animals	🐯	0.6	tiger face	animal|big|cat|predator		
animals	🦁	1.0	lion	alpha|animal|face|leo|mane|order|rawr|roar|safari|strong|zodiac		
animals	🐮	0.6	cow face	animal|farm|milk|moo		
animals	🐷	0.6	pig face	animal|bacon|farm|pork		
animals	🐽	0.6	pig nose	animal|face|farm|smell|snout		
animals	🐸	0.6	frog	animal|face		
animals	🐵	0.6	monkey face	animal|banana		
animals	🙈	0.6	see-no-evil monkey	embarrassed|face|forbidden|forgot|gesture|hide|omg|prohibited|scared|secret|smh|watch		
animals	🙉	0.6	hear-no-evil monkey	animal|ears|face|forbidden|gesture|listen|not|prohibited|secret|shh|tmi		
animals	🙊	0.6	speak-no-evil monkey	animal|face|forbidden|gesture|not|oops|prohibited|quiet|secret|stealth		
animals	🐒	0.6	monkey	animal|banana		
animals	🐔	0.6	chicken	animal|bird|ornithology		
animals	🐧	0.6	penguin	animal|antarctica|bird|ornithology		
animals	🐦	0.6	bird	animal|ornithology		
animals	🐤	0.6	baby chick	animal|bird|ornithology		
animals	🐣	0.6	hatching chick	animal|baby|bird|egg		
animals	🐥	0.6	front-facing baby chick	animal|bird|newborn|ornithology		
animals	🪿	15.0	goose	animal|bird|duck|flock|fowl|gaggle|gander|geese|honk|ornithology|silly		
animals	🦆	3.0	duck	animal|bird|ornithology		
animals	🐦‍⬛	15.0	black bird	animal|beak|caw|corvid|crow|ornithology|raven|rook		
animals	🦅	3.0	eagle	animal|bird|ornithology		
animals	🦉	3.0	owl	animal|bird|ornithology|wise		
animals	🦇	3.0	bat	animal|vampire		
animals	🐺	0.6	wolf	animal|face		
animals	🐗	0.6	boar	animal|pig		
animals	🐴	0.6	horse face	animal|dressage|equine|farm|horses		
animals	🦄	1.0	unicorn	face		
animals	🫎	15.0	moose	alces|animal|antlers|elk|mammal		
animals	🐝	0.6	honeybee	animal|bee|bumblebee|honey|insect|nature|spring		
animals	🪱	13.0	worm	animal|annelid|earthworm|parasite		
animals	🐛	0.6	bug	animal|garden|insect		
animals	🦋	3.0	butterfly	insect|pretty		
animals	🐌	0.6	snail	animal|escargot|garden|nature|slug		
animals	🐞	0.6	lady beetle	animal|garden|insect|ladybird|ladybug|nature		
animals	🐜	0.6	ant	animal|garden|insect		
animals	🪰	13.0	fly	animal|disease|insect|maggot|pest|rotting		
animals	🪲	13.0	beetle	animal|bug|insect		
animals	🪳	13.0	cockroach	animal|insect|pest|roach		
animals	🦟	11.0	mosquito	bite|disease|fever|insect|malaria|pest|virus		
animals	🦗	5.0	cricket	animal|bug|grasshopper|insect|orthoptera		
animals	🕷️	0.7	spider	animal|insect		
animals	🕸️	0.7	spider web			
animals	🦂	1.0	scorpion	scorpio|scorpius|zodiac		
animals	🐢	0.6	turtle	animal|terrapin|tortoise		
animals	🐍	0.6	snake	animal|bearer|ophiuchus|serpent|zodiac		
animals	🦎	3.0	lizard	animal|reptile		
animals	🦖	5.0	T-Rex	dinosaur|tyrannosaurus		
animals	🦕	5.0	sauropod	brachiosaurus|brontosaurus|dinosaur|diplodocus		
animals	🐙	0.6	octopus	animal|creature|ocean		
animals	🦑	3.0	squid	animal|food|mollusk		
animals	🪼	15.0	jellyfish	animal|aquarium|burn|invertebrate|jelly|life|marine|ocean|ouch|plankton|sea|sting|stinger|tentacles		
animals	🦐	3.0	shrimp	food|shellfish|small		
animals	🦞	11.0	lobster	animal|bisque|claws|seafood		
animals	🦀	1.0	crab	cancer|zodiac		
animals	🐡	0.6	blowfish	animal|fish		
animals	🐠	0.6	tropical fish	animal|fishes		
animals	🐟	0.6	fish	animal|dinner|fishes|fishing|pisces|zodiac		
animals	🐬	0.6	dolphin	animal|beach|flipper|ocean		
animals	🐳	0.6	spouting whale	animal|beach|face|ocean		
animals	🐋	1.0	whale	animal|beach|ocean		
animals	🫍	17.0	orca	marine|ocean|whale		
animals	🦈	3.0	shark	animal|fish		
animals	🦭	13.0	seal	animal|lion|ocean|sea		
animals	🐊	1.0	crocodile	animal|zoo		
animals	🐅	1.0	tiger	animal|big|cat|predator|zoo		
animals	🐆	1.0	leopard	animal|big|cat|predator|zoo		
animals	🦓	5.0	zebra	animal|stripe		
animals	🦍	3.0	gorilla	animal		
animals	🦧	12.0	orangutan	animal|ape|monkey		
animals	🫈	17.0	hairy creature	bigfoot|cryptid|forest|giant|sasquatch|woodwose|yeti		
animals	🦣	13.0	mammoth	animal|extinction|large|tusk|wooly		
animals	🐘	0.6	elephant	animal		
animals	🦛	11.0	hippopotamus	animal|hippo		
animals	🦏	3.0	rhinoceros	animal		
animals	🐪	1.0	camel	animal|desert|dromedary|hump|one		
animals	🐫	0.6	two-hump camel	animal|bactrian|desert		
animals	🦒	5.0	giraffe	animal|spots		
animals	🦘	11.0	kangaroo	animal|joey|jump|marsupial		
animals	🦬	13.0	bison	animal|buffalo|herd|wisent		
animals	🐃	1.0	water buffalo	animal|zoo		
animals	🐂	1.0	ox	animal|animals|bull|farm|taurus|zodiac		
animals	🐄	1.0	cow	animal|animals|farm|milk|moo		
animals	🫏	15.0	donkey	animal|ass|burro|hinny|mammal|mule|stubborn		
animals	🐎	0.6	horse	animal|equestrian|farm|racehorse|racing		
animals	🐖	1.0	pig	animal|bacon|farm|pork|sow		
animals	🐏	1.0	ram	animal|aries|horns|male|sheep|zodiac|zoo		
animals	🐑	0.6	ewe	animal|baa|farm|female|fluffy|lamb|sheep|wool		
animals	🦙	11.0	llama	alpaca|animal|guanaco|vicuña|wool		
animals	🐐	1.0	goat	animal|capricorn|farm|milk|zodiac		
animals	🦌	3.0	deer	animal		
animals	🐕	0.7	dog	animal|animals|dogs|pet		
animals	🐩	0.6	poodle	animal|dog|fluffy		
animals	🦮	12.0	guide dog	accessibility|animal|blind		
animals	🐕‍🦺	12.0	service dog	accessibility|animal|assistance		
animals	🐈	0.7	cat	animal|animals|cats|kitten|pet		
animals	🐈‍⬛	13.0	black cat	animal|feline|halloween|meow|unlucky		
animals	🪶	13.0	feather	bird|flight|light|plumage		
animals	🪽	15.0	wing	angelic|ascend|aviation|bird|fly|flying|heavenly|mythology|soar		
animals	🐓	1.0	rooster	animal|bird|ornithology		
animals	🦃	1.0	turkey	bird|gobble|thanksgiving		
animals	🦤	13.0	dodo	animal|bird|extinction|large|ornithology		
animals	🦚	11.0	peacock	animal|bird|colorful|ornithology|ostentatious|peahen|pretty|proud		
animals	🦜	11.0	parrot	animal|bird|ornithology|pirate|talk		
animals	🦢	11.0	swan	animal|bird|cygnet|duckling|ornithology|ugly		
animals	🦩	12.0	flamingo	animal|bird|flamboyant|ornithology|tropical		
animals	🕊️	0.7	dove	bird|fly|ornithology|peace		
animals	🐇	1.0	rabbit	animal|bunny|pet		
animals	🦝	11.0	raccoon	animal|curious|sly		
animals	🦨	12.0	skunk	animal|stink		
animals	🦡	11.0	badger	animal|honey|pester		
animals	🦫	13.0	beaver	animal|dam|teeth		
animals	🦦	12.0	otter	animal|fishing|playful		
animals	🦥	12.0	sloth	lazy|slow		
animals	🐁	1.0	mouse	animal|animals		
animals	🐀	1.0	rat	animal		
animals	🐿️	0.7	chipmunk	animal|squirrel		
animals	🦔	5.0	hedgehog	animal|spiny		
animals	🐾	0.6	paw prints	feet|paws|print		
animals	🐉	1.0	dragon	animal|fairy|fairytale|knights|tale		
animals	🐲	0.6	dragon face	animal|fairy|fairytale|tale		
animals	🐦‍🔥	15.1	phoenix	ascend|ascension|emerge|fantasy|firebird|glory|immortal|rebirth|reincarnation|reinvent|renewal|revival|revive|rise|transform		
animals	🌵	0.6	cactus	desert|drought|nature|plant		
animals	🎄	0.6	Christmas tree	celebration		
animals	🌲	1.0	evergreen tree	christmas|forest|pine		
animals	🌳	1.0	deciduous tree	forest|green|habitat|shedding		
animals	🌴	0.6	palm tree	beach|plant|tropical		
animals	🪾	16.0	leafless tree	bare|barren|branches|dead|drought|trunk|winter|wood		
animals	🪵	13.0	wood	log|lumber|timber		
animals	🌱	0.6	seedling	plant|sapling|sprout|young		
animals	🌿	0.6	herb	leaf|plant		
animals	☘️	1.0	shamrock	irish|plant		
animals	🍀	0.6	four leaf clover	4|irish|lucky|plant		
animals	🎍	0.6	pine decoration	bamboo|celebration|japanese|plant		
animals	🪴	13.0	potted plant	decor|grow|house|nurturing|pot		
animals	🎋	0.6	tanabata tree	banner|celebration|japanese		
animals	🍃	0.6	leaf fluttering in wind	blow|flutter		
animals	🍂	0.6	fallen leaf	autumn|fall|falling		
animals	🍁	0.6	maple leaf	falling		
animals	🪺	14.0	nest with eggs	bird|branch|egg|nesting		
animals	🪹	14.0	empty nest	branch|home|nesting		
animals	🍄	0.6	mushroom	fungus|toadstool		
animals	🍄‍🟫	15.1	brown mushroom	food|fungi|fungus|nature|pizza|portobello|shiitake|shroom|spore|sprout|toppings|truffle|vegetable|vegetarian|veggie		
animals	🐚	0.6	spiral shell	animal|beach|conch|sea		
animals	🪸	14.0	coral	change|climate|ocean|reef|sea		
animals	🪨	13.0	rock	boulder|heavy|solid|stone|tough		
animals	🛘	17.0	landslide	avalanche|danger|disaster|earthquake|mountain|mudslide|rocks		
animals	🌾	0.6	sheaf of rice	ear|grain|grains|plant		
animals	💐	0.6	bouquet	anniversary|birthday|date|flower|love|plant|romance		
animals	🌷	0.6	tulip	blossom|flower|growth|plant		
animals	🌹	0.6	rose	beauty|elegant|flower|love|plant|red|valentine		
animals	🥀	3.0	wilted flower	dying		
animals	🪻	15.0	hyacinth	bloom|bluebonnet|flower|indigo|lavender|lilac|lupine|plant|purple|shrub|snapdragon|spring|violet		
animals	🪷	14.0	lotus	beauty|buddhism|calm|flower|hinduism|peace|purity|serenity		
animals	🌺	0.6	hibiscus	flower|plant		
animals	🌸	0.6	cherry blossom	flower|plant|spring|springtime		
animals	🌼	0.6	blossom	buttercup|dandelion|flower|plant		
animals	🌻	0.6	sunflower	flower|outdoors|plant|sun		
animals	🌞	1.0	sun with face	beach|bright|day|heat|shine|sunny|sunshine|weather		
animals	🌝	1.0	full moon face	bright		
animals	🌛	0.6	first quarter moon face	space		
animals	🌜	0.7	last quarter moon face	dreams		
animals	🌚	1.0	new moon face	space		
animals	🌕	0.6	full moon	space		
animals	🌖	1.0	waning gibbous moon	space		
animals	🌗	1.0	last quarter moon	space		
animals	🌘	1.0	waning crescent moon	space		
animals	🌑	0.6	new moon	dark|space		
animals	🌒	1.0	waxing crescent moon	dreams|space		
animals	🌓	0.6	first quarter moon	space		
animals	🌔	0.6	waxing gibbous moon	space		
animals	🌙	0.6	crescent moon	ramadan|space		
animals	🌎	0.7	globe showing Americas	earth|world		
animals	🌍	0.7	globe showing Europe-Africa	earth|world		
animals	🌏	0.6	globe showing Asia-Australia	earth|world		
animals	🪐	12.0	ringed planet	saturn|saturnine		
animals	💫	0.6	dizzy	comic|shining|shooting|star|stars		
animals	⭐️	0.6	star	astronomy|medium|stars|white		
animals	🌟	0.6	glowing star	glittery|glow|night|shining|sparkle|win		
animals	✨	0.6	sparkles	magic|sparkle|star		
animals	⚡️	0.6	high voltage	danger|electric|electricity|lightning|nature|thunder|thunderbolt|zap		
animals	☄️	1.0	comet	space		
animals	💥	0.6	collision	bomb|boom|collide|comic|explode		
animals	🔥	0.6	fire	af|burn|flame|hot|lit|litaf|tool		
animals	🫯	17.0	fight cloud	argument|brawl|debate|disagreement|ruckus|wrestle		
animals	🌪️	0.7	tornado	cloud|weather|whirlwind		
animals	🌈	0.6	rainbow	gay|genderqueer|glbt|glbtq|lesbian|lgbt|lgbtq|lgbtqia|nature|pride|queer|rain|trans|transgender|weather		
animals	☀️	0.6	sun	bright|rays|space|sunny|weather		
animals	🌤️	0.7	sun behind small cloud	weather		
animals	⛅️	0.6	sun behind cloud	cloudy|weather		
animals	🌥️	0.7	sun behind large cloud	weather		
animals	☁️	0.6	cloud	weather		
animals	🌦️	0.7	sun behind rain cloud	weather		
animals	🌧️	0.7	cloud with rain	weather		
animals	⛈️	0.7	cloud with lightning and rain	thunder|thunderstorm		
animals	🌩️	0.7	cloud with lightning	weather		
animals	🌨️	0.7	cloud with snow	cold|weather		
animals	❄️	0.6	snowflake	cold|snow|weather		
animals	☃️	0.7	snowman	cold|man|snow		
animals	⛄️	0.6	snowman without snow	cold|man		
animals	🌬️	0.7	wind face	blow|cloud		
animals	💨	0.6	dashing away	cloud|comic|dash|fart|fast|go|gone|gotta|running|smoke		
animals	💧	0.6	droplet	cold|comic|drop|nature|sad|sweat|tear|water|weather		
animals	💦	0.6	sweat droplets	comic|drip|droplet|drops|splashing|squirt|water|wet|work|workout		
animals	🫧	14.0	bubbles	bubble|burp|clean|floating|pearl|soap|underwater		
animals	☔️	0.6	umbrella with rain drops	clothing|drop|weather		
animals	☂️	0.7	umbrella	clothing|rain		
animals	🌊	0.6	water wave	nature|ocean|surf|surfer|surfing		
animals	🌫️	0.7	fog	cloud|weather		
food	🍏	0.6	green apple	fruit		
food	🍎	0.6	red apple	diet|food|fruit|health|ripe		
food	🍐	1.0	pear	fruit		
food	🍊	0.6	tangerine	c|citrus|fruit|nectarine|orange|vitamin		
food	🍋	1.0	lemon	citrus|fruit|sour		
food	🍋‍🟩	15.1	lime	acidity|citrus|cocktail|fruit|garnish|key|margarita|mojito|refreshing|salsa|sour|tangy|tequila|tropical|zest		
food	🍌	0.6	banana	fruit|potassium		
food	🍉	0.6	watermelon	fruit		
food	🍇	0.6	grapes	dionysus|fruit|grape		
food	🍓	0.6	strawberry	berry|fruit		
food	🫐	13.0	blueberries	berries|berry|bilberry|blue|blueberry|food|fruit		
food	🍈	0.6	melon	cantaloupe|fruit		
food	🍒	0.6	cherries	berries|cherry|fruit|red		
food	🍑	0.6	peach	fruit		
food	🥭	11.0	mango	food|fruit|tropical		
food	🍍	0.6	pineapple	colada|fruit|pina|tropical		
food	🥥	5.0	coconut	colada|palm|piña		
food	🥝	3.0	kiwi fruit	food		
food	🍅	0.6	tomato	food|fruit|vegetable		
food	🍆	0.6	eggplant	aubergine|vegetable		
food	🥑	3.0	avocado	food|fruit		
food	🫛	15.0	pea pod	beans|beanstalk|edamame|legume|soybean|vegetable|veggie		
food	🥦	5.0	broccoli	cabbage|wild		
food	🥬	11.0	leafy green	bok|burgers|cabbage|choy|kale|lettuce|salad		
food	🥒	3.0	cucumber	food|pickle|vegetable		
food	🌶️	0.7	hot pepper			
food	🫑	13.0	bell pepper	capsicum|food|vegetable		
food	🌽	0.6	ear of corn	crops|farm|maize|maze		
food	🥕	3.0	carrot	food|vegetable		
food	🫒	13.0	olive	food		
food	🧄	12.0	garlic	flavoring		
food	🧅	12.0	onion	flavoring		
food	🥔	3.0	potato	food|vegetable		
food	🫜	16.0	root vegetable	beet|food|garden|radish|salad|turnip|vegetarian		
food	🍠	0.6	roasted sweet potato	food		
food	🫚	15.0	ginger root	beer|health|herb|natural|spice		
food	🥐	3.0	croissant	bread|breakfast|crescent|food|french|roll		
food	🥯	11.0	bagel	bakery|bread|breakfast|schmear		
food	🍞	0.6	bread	carbs|food|grain|loaf|restaurant|toast|wheat		
food	🥖	3.0	baguette bread	food|french		
food	🥨	5.0	pretzel	convoluted|twisted		
food	🧀	1.0	cheese wedge			
food	🥚	3.0	egg	breakfast|food		
food	🍳	0.6	cooking	breakfast|easy|egg|fry|frying|over|pan|restaurant|side|sunny|up		
food	🧈	12.0	butter	dairy		
food	🥞	3.0	pancakes	breakfast|crêpe|food|hotcake|pancake		
food	🧇	12.0	waffle	breakfast|indecisive|iron		
food	🥓	3.0	bacon	breakfast|food|meat		
food	🥩	5.0	cut of meat	chop|lambchop|porkchop|red|steak		
food	🍗	0.6	poultry leg	bone|chicken|drumstick|hungry|turkey		
food	🍖	0.6	meat on bone			
food	🦴	11.0	bone	bones|dog|skeleton|wishbone		
food	🌭	1.0	hot dog	frankfurter|hotdog|sausage		
food	🍔	0.6	hamburger	burger|eat|fast|food|hungry		
food	🍟	0.6	french fries	fast|food		
food	🍕	0.6	pizza	cheese|food|hungry|pepperoni|slice		
food	🫓	13.0	flatbread	arepa|bread|food|gordita|lavash|naan|pita		
food	🥪	5.0	sandwich	bread		
food	🥙	3.0	stuffed flatbread	falafel|food|gyro|kebab		
food	🧆	12.0	falafel	chickpea|meatball		
food	🌮	1.0	taco	mexican		
food	🌯	1.0	burrito	mexican|wrap		
food	🫔	13.0	tamale	food|mexican|pamonha|wrapped		
food	🥗	3.0	green salad	food		
food	🥘	3.0	shallow pan of food	casserole|paella		
food	🫕	13.0	fondue	cheese|chocolate|food|melted|pot|ski		
food	🥫	5.0	canned food	can		
food	🫙	14.0	jar	condiment|container|empty|nothing|sauce|store		
food	🍝	0.6	spaghetti	food|meatballs|pasta|restaurant		
food	🍜	0.6	steaming bowl	chopsticks|food|noodle|pho|ramen|soup		
food	🍲	0.6	pot of food	soup|stew		
food	🍛	0.6	curry rice	food		
food	🍣	0.6	sushi	food		
food	🍱	0.6	bento box	food		
food	🥟	5.0	dumpling	empanada|gyōza|jiaozi|pierogi|potsticker		
food	🦪	12.0	oyster	diving|pearl		
food	🍤	0.6	fried shrimp	prawn|tempura		
food	🍙	0.6	rice ball	food|japanese		
food	🍚	0.6	cooked rice	food		
food	🍘	0.6	rice cracker	food		
food	🍥	0.6	fish cake with swirl	food|pastry|restaurant		
food	🥠	5.0	fortune cookie	prophecy		
food	🥮	11.0	moon cake	autumn|festival|yuèbǐng		
food	🍢	0.6	oden	food|kebab|restaurant|seafood|skewer|stick		
food	🍡	0.6	dango	dessert|japanese|skewer|stick|sweet		
food	🍧	0.6	shaved ice	dessert|restaurant|sweet		
food	🍨	0.6	ice cream	dessert|food|restaurant|sweet		
food	🍦	0.6	soft ice cream	dessert|food|icecream|restaurant|serve|sweet		
food	🥧	5.0	pie	apple|filling|fruit|meat|pastry|pumpkin|slice		
food	🧁	11.0	cupcake	bakery|dessert|sprinkles|sugar|sweet|treat		
food	🍰	0.6	shortcake	cake|dessert|pastry|slice|sweet		
food	🎂	0.6	birthday cake	bday|celebration|dessert|happy|pastry|sweet		
food	🍮	0.6	custard	dessert|pudding|sweet		
food	🍭	0.6	lollipop	candy|dessert|food|restaurant|sweet		
food	🍬	0.6	candy	cavities|dessert|halloween|restaurant|sweet|tooth|wrapper		
food	🍫	0.6	chocolate bar	candy|dessert|halloween|sweet|tooth		
food	🍿	1.0	popcorn	corn|movie|pop		
food	🍩	0.6	doughnut	breakfast|dessert|donut|food|sweet		
food	🍪	0.6	cookie	chip|chocolate|dessert|sweet		
food	🌰	0.6	chestnut	almond|plant		
food	🥜	3.0	peanuts	food|nut|peanut|vegetable		
food	🫘	14.0	beans	food|kidney|legume|small		
food	🍯	0.6	honey pot	barrel|bear|food|honeypot|jar|sweet		
food	🥛	3.0	glass of milk	drink		
food	🫗	14.0	pouring liquid	accident|drink|empty|glass|oops|pour|spill|water		
food	🍼	1.0	baby bottle	babies|birth|born|drink|infant|milk|newborn		
food	🫖	13.0	teapot	brew|drink|food|pot|tea		
food	☕️	0.6	hot beverage	cafe|caffeine|chai|coffee|drink|morning|steaming|tea		
food	🍵	0.6	teacup without handle	beverage|cup|drink|oolong|tea		
food	🧃	12.0	beverage box	juice|straw|sweet		
food	🥤	5.0	cup with straw	drink|juice|malt|soda|soft|water		
food	🧋	13.0	bubble tea	boba|food|milk|pearl		
food	🍶	0.6	sake	bar|beverage|bottle|cup|drink|restaurant		
food	🍺	0.6	beer mug	alcohol|ale|bar|booze|drink|drinking|drinks|octoberfest|oktoberfest|pint|stein|summer		
food	🍻	0.6	clinking beer mugs	alcohol|bar|booze|bottoms|cheers|clink|drinking|drinks		
food	🥂	3.0	clinking glasses	celebrate|clink|drink|glass		
food	🍷	0.6	wine glass	alcohol|bar|beverage|booze|club|drink|drinking|drinks|restaurant		
food	🥃	3.0	tumbler glass	liquor|scotch|shot|whiskey|whisky		
food	🍸	0.6	cocktail glass	alcohol|bar|booze|club|drink|drinking|drinks|mad|martini|men		
food	🍹	0.6	tropical drink	alcohol|bar|booze|club|cocktail|drinking|drinks|drunk|mai|party|tai|tropics		
food	🧉	12.0	mate	drink		
food	🍾	1.0	bottle with popping cork	bar|drink		
food	🧊	12.0	ice	cold|cube|iceberg		
food	🥄	3.0	spoon	eat|tableware		
food	🍴	0.6	fork and knife	breakfast|breaky|cooking|cutlery|delicious|dinner|eat|feed|food|hungry|lunch|restaurant|yum|yummy		
food	🍽️	0.7	fork and knife with plate	cooking|dinner|eat		
food	🥣	5.0	bowl with spoon	breakfast|cereal|congee|oatmeal|porridge		
food	🥡	5.0	takeout box	chopsticks|delivery|food|oyster|pail		
food	🥢	5.0	chopsticks	hashi|jeotgarak|kuaizi		
food	🧂	11.0	salt	condiment|flavor|mad|salty|shaker|taste|upset		
activity	⚽️	0.6	soccer ball	football|futbol|sport		
activity	🏀	0.6	basketball	ball|hoop|sport		
activity	🏈	0.6	american football	ball|bowl|sport|super		
activity	⚾️	0.6	baseball	ball|sport		
activity	🥎	11.0	softball	ball|glove|sports|underarm		
activity	🎾	0.6	tennis	ball|racquet|sport		
activity	🏐	1.0	volleyball	ball|game		
activity	🏉	1.0	rugby football	ball|sport		
activity	🥏	11.0	flying disc	ultimate		
activity	🎱	0.6	pool 8 ball	8ball|billiard|eight|game		
activity	🪀	12.0	yo-yo	fluctuate|toy		
activity	🏓	1.0	ping pong	ball|bat|game|paddle|pingpong|table|tennis		
activity	🏸	1.0	badminton	birdie|game|racquet|shuttlecock		
activity	🏒	1.0	ice hockey	game|puck|stick		
activity	🏑	1.0	field hockey	ball|game|stick		
activity	🥍	11.0	lacrosse	ball|goal|sports|stick		
activity	🏏	1.0	cricket game	ball|bat		
activity	🪃	13.0	boomerang	rebound|repercussion|weapon		
activity	🥅	3.0	goal net			
activity	⛳️	0.6	flag in hole	golf|sport		
activity	🪁	12.0	kite	fly|soar		
activity	🛝	14.0	playground slide	amusement|park|play|playing|sliding|theme		
activity	🏹	1.0	bow and arrow	archer|archery|sagittarius|tool|weapon|zodiac		
activity	🎣	0.6	fishing pole	entertainment|fish|sport		
activity	🤿	12.0	diving mask	scuba|snorkeling		
activity	🥊	3.0	boxing glove			
activity	🥋	3.0	martial arts uniform	judo|karate|taekwondo		
activity	🎽	0.6	running shirt	athletics|sash		
activity	🛹	11.0	skateboard	board|skate|skater|wheels		
activity	🛼	13.0	roller skate	blades|skates|sport		
activity	🛷	5.0	sled	luge|sledge|sleigh|snow|toboggan		
activity	⛸️	0.7	ice skate	skating		
activity	🥌	5.0	curling stone	game|rock		
activity	🎿	0.6	skis	ski|snow|sport		
activity	⛷️	0.7	skier	ski|snow		
activity	🏂	0.6	snowboarder	ski|snow|snowboard|sport	🏂🏻,🏂🏼,🏂🏽,🏂🏾,🏂🏿	1.0
activity	🪂	12.0	parachute	hang-glide|parasail|skydive		
activity	🏋️‍♀️	4.0	woman lifting weights	barbell|bodybuilder|deadlift|lifter|powerlifting|weight|weightlifter|workout	🏋🏻‍♀️,🏋🏼‍♀️,🏋🏽‍♀️,🏋🏾‍♀️,🏋🏿‍♀️	4.0
activity	🏋️	0.7	person lifting weights	barbell|bodybuilder|deadlift|lifter|powerlifting|weight|weightlifter|workout	🏋🏻,🏋🏼,🏋🏽,🏋🏾,🏋🏿	2.0
activity	🏋️‍♂️	4.0	man lifting weights	barbell|bodybuilder|deadlift|lifter|powerlifting|weight|weightlifter|workout	🏋🏻‍♂️,🏋🏼‍♂️,🏋🏽‍♂️,🏋🏾‍♂️,🏋🏿‍♂️	4.0
activity	🤼‍♀️	4.0	women wrestling	combat|duel|grapple|ring|tournament|wrestle	🤼🏻‍♀️,🤼🏼‍♀️,🤼🏽‍♀️,🤼🏾‍♀️,🤼🏿‍♀️,👩🏻‍🫯‍👩🏼,👩🏻‍🫯‍👩🏽,👩🏻‍🫯‍👩🏾,👩🏻‍🫯‍👩🏿,👩🏼‍🫯‍👩🏻,👩🏼‍🫯‍👩🏽,👩🏼‍🫯‍👩🏾,👩🏼‍🫯‍👩🏿,👩🏽‍🫯‍👩🏻,👩🏽‍🫯‍👩🏼,👩🏽‍🫯‍👩🏾,👩🏽‍🫯‍👩🏿,👩🏾‍🫯‍👩🏻,👩🏾‍🫯‍👩🏼,👩🏾‍🫯‍👩🏽,👩🏾‍🫯‍👩🏿,👩🏿‍🫯‍👩🏻,👩🏿‍🫯‍👩🏼,👩🏿‍🫯‍👩🏽,👩🏿‍🫯‍👩🏾	17.0
activity	🤼	3.0	people wrestling	combat|duel|grapple|ring|tournament|wrestle	🤼🏻,🤼🏼,🤼🏽,🤼🏾,🤼🏿,🧑🏻‍🫯‍🧑🏼,🧑🏻‍🫯‍🧑🏽,🧑🏻‍🫯‍🧑🏾,🧑🏻‍🫯‍🧑🏿,🧑🏼‍🫯‍🧑🏻,🧑🏼‍🫯‍🧑🏽,🧑🏼‍🫯‍🧑🏾,🧑🏼‍🫯‍🧑🏿,🧑🏽‍🫯‍🧑🏻,🧑🏽‍🫯‍🧑🏼,🧑🏽‍🫯‍🧑🏾,🧑🏽‍🫯‍🧑🏿,🧑🏾‍🫯‍🧑🏻,🧑🏾‍🫯‍🧑🏼,🧑🏾‍🫯‍🧑🏽,🧑🏾‍🫯‍🧑🏿,🧑🏿‍🫯‍🧑🏻,🧑🏿‍🫯‍🧑🏼,🧑🏿‍🫯‍🧑🏽,🧑🏿‍🫯‍🧑🏾	17.0
activity	🤼‍♂️	4.0	men wrestling	combat|duel|grapple|ring|tournament|wrestle	🤼🏻‍♂️,🤼🏼‍♂️,🤼🏽‍♂️,🤼🏾‍♂️,🤼🏿‍♂️,👨🏻‍🫯‍👨🏼,👨🏻‍🫯‍👨🏽,👨🏻‍🫯‍👨🏾,👨🏻‍🫯‍👨🏿,👨🏼‍🫯‍👨🏻,👨🏼‍🫯‍👨🏽,👨🏼‍🫯‍👨🏾,👨🏼‍🫯‍👨🏿,👨🏽‍🫯‍👨🏻,👨🏽‍🫯‍👨🏼,👨🏽‍🫯‍👨🏾,👨🏽‍🫯‍👨🏿,👨🏾‍🫯‍👨🏻,👨🏾‍🫯‍👨🏼,👨🏾‍🫯‍👨🏽,👨🏾‍🫯‍👨🏿,👨🏿‍🫯‍👨🏻,👨🏿‍🫯‍👨🏼,👨🏿‍🫯‍👨🏽,👨🏿‍🫯‍👨🏾	17.0
activity	🤸‍♀️	4.0	woman cartwheeling	active|cartwheel|excited|flip|gymnastics|happy|somersault	🤸🏻‍♀️,🤸🏼‍♀️,🤸🏽‍♀️,🤸🏾‍♀️,🤸🏿‍♀️	4.0
activity	🤸	3.0	person cartwheeling	active|cartwheel|excited|flip|gymnastics|happy|somersault	🤸🏻,🤸🏼,🤸🏽,🤸🏾,🤸🏿	3.0
activity	🤸‍♂️	4.0	man cartwheeling	active|cartwheel|excited|flip|gymnastics|happy|somersault	🤸🏻‍♂️,🤸🏼‍♂️,🤸🏽‍♂️,🤸🏾‍♂️,🤸🏿‍♂️	4.0
activity	⛹️‍♀️	4.0	woman bouncing ball	athletic|basketball|championship|dribble|net|player|throw	⛹🏻‍♀️,⛹🏼‍♀️,⛹🏽‍♀️,⛹🏾‍♀️,⛹🏿‍♀️	4.0
activity	⛹️	0.7	person bouncing ball	athletic|basketball|championship|dribble|net|player|throw	⛹🏻,⛹🏼,⛹🏽,⛹🏾,⛹🏿	2.0
activity	⛹️‍♂️	4.0	man bouncing ball	athletic|basketball|championship|dribble|net|player|throw	⛹🏻‍♂️,⛹🏼‍♂️,⛹🏽‍♂️,⛹🏾‍♂️,⛹🏿‍♂️	4.0
activity	🤺	3.0	person fencing	fencer|sword		
activity	🤾‍♀️	4.0	woman playing handball	athletics|ball|catch|chuck|hurl|lob|pitch|sport|throw|toss	🤾🏻‍♀️,🤾🏼‍♀️,🤾🏽‍♀️,🤾🏾‍♀️,🤾🏿‍♀️	4.0
activity	🤾	3.0	person playing handball	athletics|ball|catch|chuck|hurl|lob|pitch|sport|throw|toss	🤾🏻,🤾🏼,🤾🏽,🤾🏾,🤾🏿	3.0
activity	🤾‍♂️	4.0	man playing handball	athletics|ball|catch|chuck|hurl|lob|pitch|sport|throw|toss	🤾🏻‍♂️,🤾🏼‍♂️,🤾🏽‍♂️,🤾🏾‍♂️,🤾🏿‍♂️	4.0
activity	🏌️‍♀️	4.0	woman golfing	ball|birdie|caddy|driving|golf|green|pga|putt|range|tee	🏌🏻‍♀️,🏌🏼‍♀️,🏌🏽‍♀️,🏌🏾‍♀️,🏌🏿‍♀️	4.0
activity	🏌️	0.7	person golfing	ball|birdie|caddy|driving|golf|green|pga|putt|range|tee	🏌🏻,🏌🏼,🏌🏽,🏌🏾,🏌🏿	4.0
activity	🏌️‍♂️	4.0	man golfing	ball|birdie|caddy|driving|golf|green|pga|putt|range|tee	🏌🏻‍♂️,🏌🏼‍♂️,🏌🏽‍♂️,🏌🏾‍♂️,🏌🏿‍♂️	4.0
activity	🏇	1.0	horse racing	jockey|racehorse|riding|sport	🏇🏻,🏇🏼,🏇🏽,🏇🏾,🏇🏿	1.0
activity	🧘‍♀️	5.0	woman in lotus position	cross|legged|legs|meditation|peace|relax|serenity|yoga|yogi|zen	🧘🏻‍♀️,🧘🏼‍♀️,🧘🏽‍♀️,🧘🏾‍♀️,🧘🏿‍♀️	5.0
activity	🧘	5.0	person in lotus position	cross|legged|legs|meditation|peace|relax|serenity|yoga|yogi|zen	🧘🏻,🧘🏼,🧘🏽,🧘🏾,🧘🏿	5.0
activity	🧘‍♂️	5.0	man in lotus position	cross|legged|legs|meditation|peace|relax|serenity|yoga|yogi|zen	🧘🏻‍♂️,🧘🏼‍♂️,🧘🏽‍♂️,🧘🏾‍♂️,🧘🏿‍♂️	5.0
activity	🏄‍♀️	4.0	woman surfing	beach|ocean|person|sport|surf|surfer|swell|waves	🏄🏻‍♀️,🏄🏼‍♀️,🏄🏽‍♀️,🏄🏾‍♀️,🏄🏿‍♀️	4.0
activity	🏄	0.6	person surfing	beach|ocean|sport|surf|surfer|swell|waves	🏄🏻,🏄🏼,🏄🏽,🏄🏾,🏄🏿	1.0
activity	🏄‍♂️	4.0	man surfing	beach|ocean|sport|surf|surfer|swell|waves	🏄🏻‍♂️,🏄🏼‍♂️,🏄🏽‍♂️,🏄🏾‍♂️,🏄🏿‍♂️	4.0
activity	🏊‍♀️	4.0	woman swimming	freestyle|man|sport|swim|swimmer|triathlon	🏊🏻‍♀️,🏊🏼‍♀️,🏊🏽‍♀️,🏊🏾‍♀️,🏊🏿‍♀️	4.0
activity	🏊	0.6	person swimming	freestyle|sport|swim|swimmer|triathlon	🏊🏻,🏊🏼,🏊🏽,🏊🏾,🏊🏿	1.0
activity	🏊‍♂️	4.0	man swimming	freestyle|sport|swim|swimmer|triathlon	🏊🏻‍♂️,🏊🏼‍♂️,🏊🏽‍♂️,🏊🏾‍♂️,🏊🏿‍♂️	4.0
activity	🤽‍♀️	4.0	woman playing water polo	sport|swimming|waterpolo	🤽🏻‍♀️,🤽🏼‍♀️,🤽🏽‍♀️,🤽🏾‍♀️,🤽🏿‍♀️	4.0
activity	🤽	3.0	person playing water polo	sport|swimming|waterpolo	🤽🏻,🤽🏼,🤽🏽,🤽🏾,🤽🏿	3.0
activity	🤽‍♂️	4.0	man playing water polo	sport|swimming|waterpolo	🤽🏻‍♂️,🤽🏼‍♂️,🤽🏽‍♂️,🤽🏾‍♂️,🤽🏿‍♂️	4.0
activity	🚣‍♀️	4.0	woman rowing boat	canoe|cruise|fishing|lake|oar|paddle|raft|river|row|rowboat	🚣🏻‍♀️,🚣🏼‍♀️,🚣🏽‍♀️,🚣🏾‍♀️,🚣🏿‍♀️	4.0
activity	🚣	1.0	person rowing boat	canoe|cruise|fishing|lake|oar|paddle|raft|river|row|rowboat	🚣🏻,🚣🏼,🚣🏽,🚣🏾,🚣🏿	1.0
activity	🚣‍♂️	4.0	man rowing boat	canoe|cruise|fishing|lake|oar|paddle|raft|river|row|rowboat	🚣🏻‍♂️,🚣🏼‍♂️,🚣🏽‍♂️,🚣🏾‍♂️,🚣🏿‍♂️	4.0
activity	🧗‍♀️	5.0	woman climbing	climb|climber|mountain|rock|scale|up	🧗🏻‍♀️,🧗🏼‍♀️,🧗🏽‍♀️,🧗🏾‍♀️,🧗🏿‍♀️	5.0
activity	🧗	5.0	person climbing	climb|climber|mountain|rock|scale|up	🧗🏻,🧗🏼,🧗🏽,🧗🏾,🧗🏿	5.0
activity	🧗‍♂️	5.0	man climbing	climb|climber|mountain|rock|scale|up	🧗🏻‍♂️,🧗🏼‍♂️,🧗🏽‍♂️,🧗🏾‍♂️,🧗🏿‍♂️	5.0
activity	🚵‍♀️	4.0	woman mountain biking	bicycle|bicyclist|bike|cycle|cyclist|riding|sport	🚵🏻‍♀️,🚵🏼‍♀️,🚵🏽‍♀️,🚵🏾‍♀️,🚵🏿‍♀️	4.0
activity	🚵	1.0	person mountain biking	bicycle|bicyclist|bike|cycle|cyclist|riding|sport	🚵🏻,🚵🏼,🚵🏽,🚵🏾,🚵🏿	1.0
activity	🚵‍♂️	4.0	man mountain biking	bicycle|bicyclist|bike|cycle|cyclist|riding|sport	🚵🏻‍♂️,🚵🏼‍♂️,🚵🏽‍♂️,🚵🏾‍♂️,🚵🏿‍♂️	4.0
activity	🚴‍♀️	4.0	woman biking	bicycle|bicyclist|bike|cycle|cyclist|riding|sport	🚴🏻‍♀️,🚴🏼‍♀️,🚴🏽‍♀️,🚴🏾‍♀️,🚴🏿‍♀️	4.0
activity	🚴	1.0	person biking	bicycle|bicyclist|bike|cycle|cyclist|riding|sport	🚴🏻,🚴🏼,🚴🏽,🚴🏾,🚴🏿	1.0
activity	🚴‍♂️	4.0	man biking	bicycle|bicyclist|bike|cycle|cyclist|riding|sport	🚴🏻‍♂️,🚴🏼‍♂️,🚴🏽‍♂️,🚴🏾‍♂️,🚴🏿‍♂️	4.0
activity	🏆	0.6	trophy	champion|champs|prize|slay|sport|victory|win|winning		
activity	🥇	3.0	1st place medal	first|gold		
activity	🥈	3.0	2nd place medal	second|silver		
activity	🥉	3.0	3rd place medal	bronze|third		
activity	🏅	1.0	sports medal	award|gold|winner		
activity	🎖️	0.7	military medal	award|celebration		
activity	🏵️	0.7	rosette	plant		
activity	🎗️	0.7	reminder ribbon	celebration		
activity	🎫	0.6	ticket	admission|stub		
activity	🎟️	0.7	admission tickets	ticket		
activity	🎪	0.6	circus tent			
activity	🤹‍♀️	4.0	woman juggling	act|balance|balancing|handle|juggle|manage|multitask|skill	🤹🏻‍♀️,🤹🏼‍♀️,🤹🏽‍♀️,🤹🏾‍♀️,🤹🏿‍♀️	4.0
activity	🤹	3.0	person juggling	act|balance|balancing|handle|juggle|manage|multitask|skill	🤹🏻,🤹🏼,🤹🏽,🤹🏾,🤹🏿	3.0
activity	🤹‍♂️	4.0	man juggling	act|balance|balancing|handle|juggle|manage|multitask|skill	🤹🏻‍♂️,🤹🏼‍♂️,🤹🏽‍♂️,🤹🏾‍♂️,🤹🏿‍♂️	4.0
activity	🎭	0.6	performing arts	actor|actress|art|entertainment|mask|theater|theatre|thespian		
activity	🩰	12.0	ballet shoes	dance		
activity	🎨	0.6	artist palette	art|artsy|arty|colorful|creative|entertainment|museum|painter|painting		
activity	🫟	16.0	splatter	drip|holi|ink|liquid|mess|paint|spill|stain		
activity	🎬	0.6	clapper board	action|movie		
activity	🎤	0.6	microphone	karaoke|mic|music|sing|sound		
activity	🎧	0.6	headphone	earbud|sound		
activity	🎼	0.6	musical score	music|note		
activity	🎹	0.6	musical keyboard	instrument|music|piano		
activity	🪇	15.0	maracas	cha|dance|instrument|music|party|percussion|rattle|shake|shaker		
activity	🥁	3.0	drum	drumsticks|music		
activity	🪘	13.0	long drum	beat|conga|instrument|rhythm		
activity	🎷	0.6	saxophone	instrument|music|sax		
activity	🎺	0.6	trumpet	instrument|music		
activity	🪊	17.0	trombone	brass|instrument|jazz|music|sad|slide		
activity	🪗	13.0	accordion	box|concertina|instrument|music|squeeze|squeezebox		
activity	🎸	0.6	guitar	instrument|music|strat		
activity	🪕	12.0	banjo	music|stringed		
activity	🪉	16.0	harp	cupid|instrument|love|music|orchestra		
activity	🎻	0.6	violin	instrument|music		
activity	🪈	15.0	flute	band|fife|flautist|instrument|marching|music|orchestra|piccolo|pipe|recorder|woodwind		
activity	🎲	0.6	game die	dice|entertainment		
activity	♟️	11.0	chess pawn	dupe|expendable		
activity	🎯	0.6	bullseye	bull|dart|direct|entertainment|game|hit|target		
activity	🎳	0.6	bowling	ball|game|sport|strike		
activity	🎮	0.6	video game	controller|entertainment		
activity	🎰	0.6	slot machine	casino|gamble|gambling|game|slots		
activity	🧩	11.0	puzzle piece	clue|interlocking|jigsaw		
travel	🚗	0.6	automobile	car|driving|vehicle		
travel	🚕	0.6	taxi	cab|cabbie|car|drive|vehicle|yellow		
travel	🚙	0.6	sport utility vehicle	car|drive|recreational|sportutility		
travel	🚌	0.6	bus	school|vehicle		
travel	🚎	1.0	trolleybus	bus|tram|trolley		
travel	🏎️	0.7	racing car	zoom		
travel	🚓	0.6	police car	5–0|cops|patrol		
travel	🚑	0.6	ambulance	emergency|vehicle		
travel	🚒	0.6	fire engine	truck		
travel	🚐	1.0	minibus	bus|drive|van|vehicle		
travel	🛻	13.0	pickup truck	automobile|car|flatbed|pick-up|transportation		
travel	🚚	0.6	delivery truck	car|drive|vehicle		
travel	🚛	1.0	articulated lorry	car|drive|move|semi|truck|vehicle		
travel	🚜	1.0	tractor	vehicle		
travel	🦯	12.0	white cane	accessibility|blind|probing		
travel	🦽	12.0	manual wheelchair	accessibility		
travel	🦼	12.0	motorized wheelchair	accessibility		
travel	🩼	14.0	crutch	aid|cane|disability|help|hurt|injured|mobility|stick		
travel	🛴	3.0	kick scooter			
travel	🚲	0.6	bicycle	bike|class|cycle|cycling|cyclist|gang|ride|spin|spinning		
travel	🛵	3.0	motor scooter			
travel	🏍️	0.7	motorcycle	racing		
travel	🛺	12.0	auto rickshaw	tuk		
travel	🛞	14.0	wheel	car|circle|tire|turn|vehicle		
travel	🚨	0.6	police car light	alarm|alert|beacon|emergency|revolving|siren		
travel	🚔	0.7	oncoming police car			
travel	🚍	0.7	oncoming bus	cars		
travel	🚘	0.7	oncoming automobile	car|cars|drove|vehicle		
travel	🚖	1.0	oncoming taxi	cab|cabbie|cars|drove|hail|yellow		
travel	🚡	1.0	aerial tramway	cable|car|gondola|ropeway		
travel	🚠	1.0	mountain cableway	cable|gondola|lift|ski		
travel	🚟	1.0	suspension railway			
travel	🚃	0.6	railway car	electric|train|tram|travel|trolleybus		
travel	🚋	1.0	tram car	bus|trolley|trolleybus		
travel	🚞	1.0	mountain railway	car|trip		
travel	🚝	1.0	monorail	vehicle		
travel	🚄	0.6	high-speed train	railway|shinkansen		
travel	🚅	0.6	bullet train	high-speed|nose|railway|shinkansen|speed|travel		
travel	🚈	1.0	light rail	arrived|monorail|railway		
travel	🚂	1.0	locomotive	caboose|engine|railway|steam|train|trains|travel		
travel	🚆	1.0	train	arrived|choo|railway		
travel	🚇	0.6	metro	subway|travel		
travel	🚊	1.0	tram	trolleybus		
travel	🚉	0.6	station	railway|train		
travel	✈️	0.6	airplane	aeroplane|fly|flying|jet|plane|travel		
travel	🛫	1.0	airplane departure	aeroplane|check-in|departures|plane		
travel	🛬	1.0	airplane arrival	aeroplane|arrivals|arriving|landing|plane		
travel	🛩️	0.7	small airplane	aeroplane|plane		
travel	💺	0.6	seat	chair		
travel	🛰️	0.7	satellite	space		
travel	🚀	0.6	rocket	launch|rockets|space|travel		
travel	🛸	5.0	flying saucer	aliens|extra|terrestrial|ufo		
travel	🚁	1.0	helicopter	copter|roflcopter|travel|vehicle		
travel	🛶	3.0	canoe	boat		
travel	⛵️	0.6	sailboat	boat|resort|sailing|sea|yacht		
travel	🚤	0.6	speedboat	billionaire|boat|lake|luxury|millionaire|summer|travel		
travel	🛥️	0.7	motor boat	motorboat		
travel	🛳️	0.7	passenger ship			
travel	⛴️	0.7	ferry	boat|passenger		
travel	🚢	0.6	ship	boat|passenger|travel		
travel	🛟	14.0	ring buoy	float|life|lifesaver|preserver|rescue|safety|save|saver|swim		
travel	⚓️	0.6	anchor	ship|tool		
travel	🪝	13.0	hook	catch|crook|curve|ensnare|point|selling		
travel	⛽️	0.6	fuel pump	diesel|fuelpump|gas|gasoline|station		
travel	🚧	0.6	construction	barrier		
travel	🚦	1.0	vertical traffic light	drove|intersection|signal|stop|stoplight		
travel	🚥	0.6	horizontal traffic light	intersection|signal|stop|stoplight		
travel	🚏	0.6	bus stop	busstop		
travel	🗺️	0.7	world map			
travel	🗿	0.6	moai	face|moyai|statue|stoneface|travel		
travel	🗽	0.6	Statue of Liberty	new|ny|nyc|york		
travel	🗼	0.6	Tokyo tower			
travel	🏰	0.6	castle	building|european		
travel	🏯	0.6	Japanese castle	building		
travel	🏟️	0.7	stadium			
travel	🎡	0.6	ferris wheel	amusement|park|theme		
travel	🎢	0.6	roller coaster	amusement|park|theme		
travel	🎠	0.6	carousel horse	entertainment		
travel	⛲️	0.6	fountain			
travel	⛱️	0.7	umbrella on ground	rain|sun		
travel	🏖️	0.7	beach with umbrella			
travel	🏝️	0.7	desert island			
travel	🏜️	0.7	desert			
travel	🌋	0.6	volcano	eruption|mountain|nature		
travel	⛰️	0.7	mountain			
travel	🏔️	0.7	snow-capped mountain	cold		
travel	🗻	0.6	mount fuji	mountain|nature		
travel	🏕️	0.7	camping			
travel	⛺️	0.6	tent	camping		
travel	🛖	13.0	hut	home|house|roundhouse|shelter|yurt		
travel	🏠	0.6	house	building|country|heart|home|ranch|settle|simple|suburban|suburbia|where		
travel	🏡	0.6	house with garden	building|country|heart|home|ranch|settle|simple|suburban|suburbia|where		
travel	🏘️	0.7	houses	house		
travel	🏚️	0.7	derelict house	home		
travel	🏗️	0.7	building construction	crane		
travel	🏭	0.6	factory	building		
travel	🏢	0.6	office building	city|cubical|job		
travel	🏬	0.6	department store	building		
travel	🏣	0.6	Japanese post office	building		
travel	🏤	1.0	post office	building|european		
travel	🏥	0.6	hospital	building|doctor|medicine		
travel	🏦	0.6	bank	building		
travel	🏨	0.6	hotel	building		
travel	🏪	0.6	convenience store	24|building|hours		
travel	🏫	0.6	school	building		
travel	🏩	0.6	love hotel	building		
travel	💒	0.6	wedding	chapel|hitched|nuptials|romance		
travel	🏛️	0.7	classical building			
travel	⛪️	0.6	church	bless|chapel|christian|cross|religion		
travel	🕌	1.0	mosque	islam|masjid|muslim|religion		
travel	🕍	1.0	synagogue	jew|jewish|judaism|religion|temple		
travel	🛕	12.0	hindu temple			
travel	🕋	1.0	kaaba	hajj|islam|muslim|religion|umrah		
travel	⛩️	0.7	shinto shrine	religion		
travel	🛤️	0.7	railway track	train		
travel	🛣️	0.7	motorway	highway|road		
travel	🗾	0.6	map of Japan			
travel	🎑	0.6	moon viewing ceremony	celebration		
travel	🏞️	0.7	national park			
travel	🌅	0.6	sunrise	morning|nature|sun		
travel	🌄	0.6	sunrise over mountains	morning|sun		
travel	🌠	0.6	shooting star	falling|night|space		
travel	🎇	0.6	sparkler	boom|celebration|fireworks|sparkle		
travel	🎆	0.6	fireworks	boom|celebration|entertainment|yolo		
travel	🌇	0.6	sunset	building|dusk|sun		
travel	🌆	0.6	cityscape at dusk	building|city|evening|landscape|sun|sunset		
travel	🏙️	0.7	cityscape	city		
travel	🌃	0.6	night with stars	star		
travel	🌌	0.6	milky way	space		
travel	🌉	0.6	bridge at night			
travel	🌁	0.6	foggy	fog		
objects	⌚️	0.6	watch	clock|time		
objects	📱	0.6	mobile phone	cell|communication|telephone		
objects	📲	0.6	mobile phone with arrow	build|call|cell|communication|receive|telephone		
objects	💻	0.6	laptop	computer|office|pc|personal		
objects	⌨️	1.0	keyboard	computer		
objects	🖥️	0.7	desktop computer	monitor		
objects	🖨️	0.7	printer	computer		
objects	🖱️	0.7	computer mouse			
objects	🖲️	0.7	trackball	computer		
objects	🕹️	0.7	joystick	game|video|videogame		
objects	🗜️	0.7	clamp	compress|tool|vice		
objects	💽	0.6	computer disk	minidisk|optical		
objects	💾	0.6	floppy disk	computer		
objects	💿	0.6	optical disk	blu-ray|cd|computer|dvd		
objects	📀	0.6	dvd	blu-ray|cd|computer|disk|optical		
objects	📼	0.6	videocassette	old|school|tape|vcr|vhs|video		
objects	📷	0.6	camera	photo|selfie|snap|tbt|trip|video		
objects	📸	1.0	camera with flash	video		
objects	📹	0.6	video camera	camcorder|tbt		
objects	🎥	0.6	movie camera	bollywood|cinema|film|hollywood|record		
objects	📽️	0.7	film projector	cinema|movie|video		
objects	🎞️	0.7	film frames	cinema|movie		
objects	📞	0.6	telephone receiver	communication|phone|voip		
objects	☎️	0.6	telephone	phone		
objects	📟	0.6	pager	communication		
objects	📠	0.6	fax machine	communication		
objects	📺	0.6	television	tv|video		
objects	📻	0.6	radio	entertainment|tbt|video		
objects	🎙️	0.7	studio microphone	mic|music		
objects	🎚️	0.7	level slider	music		
objects	🎛️	0.7	control knobs	music		
objects	🧭	11.0	compass	direction|magnetic|navigation|orienteering		
objects	⏱️	1.0	stopwatch	clock|time		
objects	⏲️	1.0	timer clock			
objects	⏰	0.6	alarm clock	hours|hrs|late|time|waiting		
objects	🕰️	0.7	mantelpiece clock	time		
objects	⌛️	0.6	hourglass done	sand|time|timer		
objects	⏳	0.6	hourglass not done	flowing|hours|sand|timer|waiting|yolo		
objects	📡	0.6	satellite antenna	aliens|contact|dish|science		
objects	🔋	0.6	battery			
objects	🪫	14.0	low battery	drained|electronic|energy|power		
objects	🔌	0.6	electric plug	electricity		
objects	💡	0.6	light bulb	comic|electric|idea		
objects	🔦	0.6	flashlight	electric|light|tool|torch		
objects	🕯️	0.7	candle	light		
objects	🪔	12.0	diya lamp	light|oil		
objects	🧯	11.0	fire extinguisher	extinguish|quench		
objects	🛢️	0.7	oil drum			
objects	💸	0.6	money with wings	bank|banknote|bill|billion|cash|dollar|fly|million|note|pay		
objects	💵	0.6	dollar banknote	bank|bill|currency|money|note		
objects	💴	0.6	yen banknote	bank|bill|currency|money|note		
objects	💶	1.0	euro banknote	100|bank|bill|currency|money|note|rich		
objects	💷	1.0	pound banknote	bank|bill|billion|cash|currency|money|note|pounds		
objects	🪙	13.0	coin	dollar|euro|gold|metal|money|rich|silver|treasure		
objects	💰	0.6	money bag	bank|bet|billion|cash|cost|dollar|gold|million|moneybag|paid|paying|pot|rich|win		
objects	💳	0.6	credit card	bank|cash|charge|money|pay		
objects	🪪	14.0	identification card	credentials|document|id|license|security		
objects	💎	0.6	gem stone	diamond|engagement|jewel|money|romance|wedding		
objects	🪎	17.0	treasure chest	gem|gold|jewels|loot|money|prize|silver|valuables|wealth		
objects	⚖️	1.0	balance scale	justice|libra|scales|tool|weight|zodiac		
objects	🪜	13.0	ladder	climb|rung|step		
objects	🧰	11.0	toolbox	box|chest|mechanic|red|tool		
objects	🪛	13.0	screwdriver	flathead|handy|screw|tool		
objects	🔧	0.6	wrench	home|improvement|spanner|tool		
objects	🔨	0.6	hammer	home|improvement|repairs|tool		
objects	⚒️	1.0	hammer and pick	tool		
objects	🛠️	0.7	hammer and wrench	spanner|tool		
objects	⛏️	0.7	pick	hammer|mining|tool		
objects	🪏	16.0	shovel	bury|dig|garden|hole|plant|scoop|snow|spade		
objects	🪚	13.0	carpentry saw	carpenter|cut|lumber|tool|trim		
objects	🔩	0.6	nut and bolt	home|improvement|tool		
objects	⚙️	1.0	gear	cog|cogwheel|tool		
objects	🪤	13.0	mouse trap	bait|cheese|lure|mousetrap|snare		
objects	🧱	11.0	brick	bricks|clay|mortar|wall		
objects	⛓️	0.7	chains	chain		
objects	⛓️‍💥	15.1	broken chain	break|breaking|cuffs|freedom		
objects	🧲	11.0	magnet	attraction|horseshoe|magnetic|negative|positive|shape|u		
objects	🔫	0.6	water pistol	gun|handgun|revolver|tool|weapon		
objects	💣	0.6	bomb	boom|comic|dangerous|explosion|hot		
objects	🧨	11.0	firecracker	dynamite|explosive|fire|fireworks|light|pop|popping|spark		
objects	🪓	12.0	axe	ax|chop|hatchet|split|wood		
objects	🔪	0.6	kitchen knife	chef|cooking|hocho|tool|weapon		
objects	🗡️	0.7	dagger	knife|weapon		
objects	⚔️	1.0	crossed swords	weapon		
objects	🛡️	0.7	shield	weapon		
objects	🚬	0.6	cigarette	smoking		
objects	⚰️	1.0	coffin	dead|death|vampire		
objects	🪦	13.0	headstone	cemetery|dead|grave|graveyard|memorial|rip|tomb|tombstone		
objects	⚱️	1.0	funeral urn	ashes|death		
objects	🏺	1.0	amphora	aquarius|cooking|drink|jug|tool|weapon|zodiac		
objects	🔮	0.6	crystal ball	fairy|fairytale|fantasy|fortune|future|magic|tale|tool		
objects	📿	1.0	prayer beads	clothing|necklace|religion		
objects	🧿	11.0	nazar amulet	bead|blue|charm|evil-eye|talisman		
objects	🪬	14.0	hamsa	amulet|fatima|fortune|guide|hand|mary|miriam|palm|protect|protection		
objects	💈	0.6	barber pole	cut|fresh|haircut|shave		
objects	⚗️	1.0	alembic	chemistry|tool		
objects	🔭	1.0	telescope	contact|extraterrestrial|science|tool		
objects	🔬	1.0	microscope	experiment|lab|science|tool		
objects	🕳️	0.7	hole			
objects	🩻	14.0	x-ray	bones|doctor|medical|skeleton|skull|xray		
objects	🩹	12.0	adhesive bandage			
objects	🩺	12.0	stethoscope	doctor|heart|medicine		
objects	💊	0.6	pill	doctor|drugs|medicated|medicine|pills|sick|vitamin		
objects	💉	0.6	syringe	doctor|flu|medicine|needle|shot|sick|tool|vaccination		
objects	🩸	12.0	drop of blood	bleed|donation|injury|medicine|menstruation		
objects	🧬	11.0	dna	biologist|evolution|gene|genetics|life		
objects	🦠	11.0	microbe	amoeba|bacteria|science|virus		
objects	🧫	11.0	petri dish	bacteria|biologist|biology|culture|lab		
objects	🧪	11.0	test tube	chemist|chemistry|experiment|lab|science		
objects	🌡️	0.7	thermometer	weather		
objects	🧹	11.0	broom	cleaning|sweeping|witch		
objects	🪠	13.0	plunger	cup|force|plumber|poop|suction|toilet		
objects	🧺	11.0	basket	farming|laundry|picnic		
objects	🧻	11.0	roll of paper	toilet|towels		
objects	🚽	0.6	toilet	bathroom		
objects	🚰	1.0	potable water	drinking		
objects	🚿	1.0	shower	water		
objects	🛁	1.0	bathtub	bath		
objects	🛀	0.6	person taking bath	bathtub|tub	🛀🏻,🛀🏼,🛀🏽,🛀🏾,🛀🏿	1.0
objects	🧼	11.0	soap	bar|bathing|clean|cleaning|lather|soapdish		
objects	🪥	13.0	toothbrush	bathroom|brush|clean|dental|hygiene|teeth|toiletry		
objects	🪒	12.0	razor	sharp|shave		
objects	🪮	15.0	hair pick	afro|comb|groom		
objects	🧽	11.0	sponge	absorbing|cleaning|porous|soak		
objects	🪣	13.0	bucket	cask|pail|vat		
objects	🧴	11.0	lotion bottle	moisturizer|shampoo|sunscreen		
objects	🛎️	0.7	bellhop bell	hotel		
objects	🔑	0.6	key	keys|lock|major|password|unlock		
objects	🗝️	0.7	old key	clue|lock		
objects	🚪	0.6	door	back|closet|front		
objects	🪑	12.0	chair	seat|sit		
objects	🛋️	0.7	couch and lamp	hotel		
objects	🛏️	0.7	bed	hotel|sleep		
objects	🛌	1.0	person in bed	bedtime|good|goodnight|hotel|nap|night|sleep|tired|zzz	🛌🏻,🛌🏼,🛌🏽,🛌🏾,🛌🏿	4.0
objects	🧸	11.0	teddy bear	plaything|plush|stuffed|toy		
objects	🪆	13.0	nesting dolls	babooshka|baboushka|babushka|doll|matryoshka|russia		
objects	🖼️	0.7	framed picture	art|frame|museum|painting		
objects	🪞	13.0	mirror	makeup|reflection|reflector|speculum		
objects	🪟	13.0	window	air|frame|fresh|opening|transparent|view		
objects	🛍️	0.7	shopping bags	bag|hotel		
objects	🛒	3.0	shopping cart	trolley		
objects	🎁	0.6	wrapped gift	birthday|bow|box|celebration|christmas|present|surprise		
objects	🎈	0.6	balloon	birthday|celebrate|celebration		
objects	🎏	0.6	carp streamer	celebration		
objects	🎀	0.6	ribbon	celebration		
objects	🪄	13.0	magic wand	magician|witch|wizard		
objects	🪅	13.0	piñata	candy|celebrate|celebration|cinco|de|festive|mayo|party|pinada|pinata		
objects	🎊	0.6	confetti ball	celebrate|celebration|party|woohoo		
objects	🎉	0.6	party popper	awesome|birthday|celebrate|celebration|excited|hooray|tada|woohoo		
objects	🎎	0.6	Japanese dolls	celebration|doll|festival		
objects	🪭	15.0	folding hand fan	clack|clap|cool|cooling|dance|flirt|flutter|hot|shy		
objects	🏮	0.6	red paper lantern	bar|light|restaurant		
objects	🎐	0.6	wind chime	bell|celebration		
objects	🪩	14.0	mirror ball	dance|disco|glitter|party		
objects	🧧	11.0	red envelope	gift|good|hóngbāo|lai|luck|money|see		
objects	✉️	0.6	envelope	e-mail|email|letter		
objects	📩	0.6	envelope with arrow	communication|down|e-mail|email|letter|mail|outgoing|send|sent		
objects	📨	0.6	incoming envelope	delivering|e-mail|email|letter|mail|receive|sent		
objects	📧	0.6	e-mail	email|letter		
objects	💌	0.6	love letter	heart|mail|romance|valentine		
objects	📥	0.6	inbox tray	box|email|letter|mail|receive|zero		
objects	📤	0.6	outbox tray	box|email|letter|mail|sent		
objects	📦	0.6	package	box|communication|delivery|parcel|shipping		
objects	🏷️	0.7	label	tag		
objects	🪧	13.0	placard	card|demonstration|notice|picket|plaque|protest|sign		
objects	📪	0.6	closed mailbox with lowered flag	mail|postbox		
objects	📫	0.6	closed mailbox with raised flag	communication|mail|postbox		
objects	📬	0.7	open mailbox with raised flag	mail|postbox		
objects	📭	0.7	open mailbox with lowered flag	mail|postbox		
objects	📮	0.6	postbox	mail|mailbox		
objects	📯	1.0	postal horn	post		
objects	📜	0.6	scroll	paper		
objects	📃	0.6	page with curl	document|paper		
objects	📄	0.6	page facing up	document|paper		
objects	📑	0.6	bookmark tabs	mark|marker		
objects	🧾	11.0	receipt	accounting|bookkeeping|evidence|invoice|proof		
objects	📊	0.6	bar chart	data|graph		
objects	📈	0.6	chart increasing	data|graph|growth|right|trend|up|upward		
objects	📉	0.6	chart decreasing	data|down|downward|graph|negative|trend		
objects	🗒️	0.7	spiral notepad	note|pad		
objects	🗓️	0.7	spiral calendar	pad		
objects	📆	0.6	tear-off calendar			
objects	📅	0.6	calendar	date		
objects	🗑️	0.7	wastebasket	can|garbage|trash|waste		
objects	📇	0.6	card index	old|rolodex|school		
objects	🗃️	0.7	card file box			
objects	🗳️	0.7	ballot box with ballot			
objects	🗄️	0.7	file cabinet	filing|paper		
objects	📋	0.6	clipboard	do|list|notes		
objects	📁	0.6	file folder			
objects	📂	0.6	open file folder			
objects	🗂️	0.7	card index dividers			
objects	🗞️	0.7	rolled-up newspaper	news|paper		
objects	📰	0.6	newspaper	communication|news|paper		
objects	📓	0.6	notebook			
objects	📔	0.6	notebook with decorative cover	book|decorated|education|school|writing		
objects	📒	0.6	ledger	notebook		
objects	📕	0.6	closed book	education		
objects	📗	0.6	green book	education|fantasy|library|reading		
objects	📘	0.6	blue book	education|fantasy|library|reading		
objects	📙	0.6	orange book	education|fantasy|library|reading		
objects	📚	0.6	books	book|education|fantasy|knowledge|library|novels|reading|school|study		
objects	📖	0.6	open book	education|fantasy|knowledge|library|novels|reading		
objects	🔖	0.6	bookmark	mark		
objects	🧷	11.0	safety pin	diaper|punk|rock		
objects	🔗	0.6	link	links		
objects	📎	0.6	paperclip			
objects	🖇️	0.7	linked paperclips	link|paperclip		
objects	📐	0.6	triangular ruler	angle|math|rule|set|slide|triangle		
objects	📏	0.6	straight ruler	angle|edge|math|straightedge		
objects	🧮	11.0	abacus	calculation|calculator		
objects	📌	0.6	pushpin	collage|pin		
objects	📍	0.6	round pushpin	location|map|pin		
objects	✂️	0.6	scissors	cut|cutting|paper|tool		
objects	🖊️	0.7	pen	ballpoint		
objects	🖋️	0.7	fountain pen			
objects	✒️	0.6	black nib	pen		
objects	🖌️	0.7	paintbrush	painting		
objects	🖍️	0.7	crayon			
objects	📝	0.6	memo	communication|media|notes|pencil		
objects	✏️	0.6	pencil			
objects	🔍	0.6	magnifying glass tilted left	lab|left-pointing|science|search|tool		
objects	🔎	0.6	magnifying glass tilted right	contact|lab|right-pointing|science|search|tool		
objects	🔏	0.6	locked with pen	ink|lock|nib|privacy		
objects	🔐	0.6	locked with key	bike|closed|lock|secure		
objects	🔒	0.6	locked	closed|lock|private		
objects	🔓	0.6	unlocked	cracked|lock|open|unlock		
symbols	🩷	15.0	pink heart	143|adorable|cute|emotion|ily|like|love|special|sweet		
symbols	❤️	0.6	red heart	emotion|love		
symbols	🧡	5.0	orange heart	143		
symbols	💛	0.6	yellow heart	143|cardiac|emotion|ily|love		
symbols	💚	0.6	green heart	143|emotion|ily|love|romantic		
symbols	🩵	15.0	light blue heart	143|cute|cyan|emotion|ily|like|love|sky|special|teal		
symbols	💙	0.6	blue heart	143|emotion|ily|love|romance		
symbols	💜	0.6	purple heart	143|bestest|emotion|ily|love		
symbols	🖤	3.0	black heart	evil|wicked		
symbols	🩶	15.0	grey heart	143|emotion|gray|ily|love|silver|slate|special		
symbols	🤍	12.0	white heart	143		
symbols	🤎	12.0	brown heart	143		
symbols	💔	0.6	broken heart	break|crushed|emotion|heartbroken|lonely|sad		
symbols	❤️‍🔥	13.1	heart on fire	burn|love|lust|sacred		
symbols	❤️‍🩹	13.1	mending heart	healthier|improving|recovering|recuperating|well		
symbols	❣️	1.0	heart exclamation	heavy|mark|punctuation		
symbols	💕	0.6	two hearts	143|anniversary|date|dating|emotion|heart|ily|kisses|love|loving|xoxo		
symbols	💞	0.6	revolving hearts	143|adorbs|anniversary|emotion|heart		
symbols	💓	0.6	beating heart	143|cardio|emotion|heartbeat|ily|love|pulsating|pulse		
symbols	💗	0.6	growing heart	143|emotion|excited|heartpulse|ily|kisses|muah|nervous|pulse|xoxo		
symbols	💖	0.6	sparkling heart	143|emotion|excited|good|ily|kisses|morning|night|sparkle|xoxo		
symbols	💘	0.6	heart with arrow	143|adorbs|cupid|date|emotion|ily|love|romance|valentine		
symbols	💝	0.6	heart with ribbon	143|anniversary|emotion|ily|kisses|valentine|xoxo		
symbols	💟	0.6	heart decoration	143|emotion|hearth|purple|white		
symbols	☮️	1.0	peace symbol	healing|peaceful		
symbols	✝️	0.7	latin cross	christ|christian|religion		
symbols	☪️	0.7	star and crescent	islam|muslim|ramadan|religion		
symbols	🕉️	0.7	om	hindu|religion		
symbols	☸️	0.7	wheel of dharma	buddhist|religion		
symbols	🪯	15.0	khanda	deg|fateh|khalsa|religion|sikh|sikhism|tegh		
symbols	✡️	0.7	star of David	jew|jewish|judaism|religion		
symbols	🔯	0.6	dotted six-pointed star	fortune|jewish|judaism		
symbols	🕎	1.0	menorah	candelabrum|candlestick|hanukkah|jewish|judaism|religion		
symbols	☯️	0.7	yin yang	difficult|lives|religion|tao|taoist|total|yinyang		
symbols	☦️	1.0	orthodox cross	christian|religion		
symbols	🛐	1.0	place of worship	pray|religion		
symbols	⛎	0.6	Ophiuchus	bearer|serpent|snake|zodiac		
symbols	♈️	0.6	Aries	horoscope|ram|zodiac		
symbols	♉️	0.6	Taurus	bull|horoscope|ox|zodiac		
symbols	♊️	0.6	Gemini	horoscope|twins|zodiac		
symbols	♋️	0.6	Cancer	crab|horoscope|zodiac		
symbols	♌️	0.6	Leo	horoscope|lion|zodiac		
symbols	♍️	0.6	Virgo	horoscope|zodiac		
symbols	♎️	0.6	Libra	balance|horoscope|justice|scales|zodiac		
symbols	♏️	0.6	Scorpio	horoscope|scorpion|scorpius|zodiac		
symbols	♐️	0.6	Sagittarius	archer|horoscope|zodiac		
symbols	♑️	0.6	Capricorn	goat|horoscope|zodiac		
symbols	♒️	0.6	Aquarius	bearer|horoscope|water|zodiac		
symbols	♓️	0.6	Pisces	fish|horoscope|zodiac		
symbols	🆔	0.6	ID button	identity		
symbols	⚛️	1.0	atom symbol	atheist		
symbols	🉑	0.6	Japanese “acceptable” button	ideograph		
symbols	☢️	1.0	radioactive	sign		
symbols	☣️	1.0	biohazard	sign		
symbols	📴	0.6	mobile phone off	cell|telephone		
symbols	📳	0.6	vibration mode	cell|communication|mobile|phone|telephone		
symbols	🈶	0.6	Japanese “not free of charge” button	ideograph		
symbols	🈚️	0.6	Japanese “free of charge” button	ideograph		
symbols	🈸	0.6	Japanese “application” button	ideograph		
symbols	🈺	0.6	Japanese “open for business” button	ideograph		
symbols	🈷️	0.6	Japanese “monthly amount” button	ideograph		
symbols	✴️	0.6	eight-pointed star			
symbols	🆚	0.6	VS button	versus		
symbols	💮	0.6	white flower			
symbols	🉐	0.6	Japanese “bargain” button	ideograph		
symbols	㊙️	0.6	Japanese “secret” button	ideograph		
symbols	㊗️	0.6	Japanese “congratulations” button	ideograph		
symbols	🈴	0.6	Japanese “passing grade” button	ideograph		
symbols	🈵	0.6	Japanese “no vacancy” button	ideograph		
symbols	🈹	0.6	Japanese “discount” button	ideograph		
symbols	🈲	0.6	Japanese “prohibited” button	ideograph		
symbols	🅰️	0.6	A button (blood type)			
symbols	🅱️	0.6	B button (blood type)			
symbols	🆎	0.6	AB button (blood type)			
symbols	🆑	0.6	CL button			
symbols	🅾️	0.6	O button (blood type)			
symbols	🆘	0.6	SOS button	help		
symbols	❌	0.6	cross mark	cancel|multiplication|multiply|x		
symbols	⭕️	0.6	hollow red circle	heavy|large|o		
symbols	🛑	3.0	stop sign	octagonal		
symbols	⛔️	0.6	no entry	do|fail|forbidden|not|pass|prohibited|traffic		
symbols	📛	0.6	name badge			
symbols	🚫	0.6	prohibited	entry|forbidden|no|not|smoke		
symbols	💯	0.6	hundred points	100|a+|agree|clearly|definitely|faithful|fleek|full|keep|perfect|point|score|true|truth|yup		
symbols	💢	0.6	anger symbol	angry|comic|mad|upset		
symbols	♨️	0.6	hot springs	hotsprings|steaming		
symbols	🚷	1.0	no pedestrians	forbidden|not|pedestrian|prohibited		
symbols	🚯	1.0	no littering	forbidden|litter|not|prohibited		
symbols	🚳	1.0	no bicycles	bicycle|bike|forbidden|not|prohibited		
symbols	🚱	1.0	non-potable water	dry|non-drinking|prohibited		
symbols	🔞	0.6	no one under eighteen	18|age|forbidden|not|prohibited|restriction|underage		
symbols	📵	1.0	no mobile phones	cell|forbidden|not|phone|prohibited|telephone		
symbols	🚭	0.6	no smoking	forbidden|not|prohibited|smoke		
symbols	❗️	0.6	red exclamation mark	punctuation		
symbols	❕	0.6	white exclamation mark	outlined|punctuation		
symbols	❓	0.6	red question mark	punctuation		
symbols	❔	0.6	white question mark	outlined|punctuation		
symbols	‼️	0.6	double exclamation mark	bangbang|punctuation		
symbols	⁉️	0.6	exclamation question mark	interrobang|punctuation		
symbols	🔅	1.0	dim button	brightness|low		
symbols	🔆	1.0	bright button	brightness|light		
symbols	〽️	0.6	part alternation mark			
symbols	⚠️	0.6	warning	caution		
symbols	🚸	1.0	children crossing	child|pedestrian|traffic		
symbols	🔱	0.6	trident emblem	anchor|poseidon|ship|tool		
symbols	⚜️	1.0	fleur-de-lis	knights		
symbols	🔰	0.6	Japanese symbol for beginner	chevron|green|leaf|tool|yellow		
symbols	♻️	0.6	recycling symbol	recycle		
symbols	✅	0.6	check mark button	checked|checkmark|complete|completed|done|fixed|tick		
symbols	🈯️	0.6	Japanese “reserved” button	ideograph		
symbols	💹	0.6	chart increasing with yen	bank|currency|graph|growth|market|money|rise|trend|upward		
symbols	❇️	0.6	sparkle			
symbols	✳️	0.6	eight-spoked asterisk			
symbols	❎	0.6	cross mark button	multiplication|multiply|square|x		
symbols	🌐	1.0	globe with meridians	earth|internet|web|world|worldwide		
symbols	💠	0.6	diamond with a dot	comic|geometric		
symbols	Ⓜ️	0.6	circled M	circle		
symbols	🌀	0.6	cyclone	dizzy|hurricane|twister|typhoon|weather		
symbols	💤	0.6	ZZZ	comic|good|goodnight|night|sleep|sleeping|sleepy|tired		
symbols	🏧	0.6	ATM sign	automated|bank|cash|money|teller		
symbols	🚾	0.6	water closet	bathroom|lavatory|restroom|toilet|wc		
symbols	♿️	0.6	wheelchair symbol	access|handicap		
symbols	🅿️	0.6	P button	parking		
symbols	🛗	13.0	elevator	accessibility|hoist|lift		
symbols	🈳	0.6	Japanese “vacancy” button	ideograph		
symbols	🈂️	0.6	Japanese “service charge” button	katakana		
symbols	🛂	1.0	passport control			
symbols	🛃	1.0	customs	packing		
symbols	🛄	1.0	baggage claim	arrived|bags|case|checked|journey|packing|plane|ready|travel|trip		
symbols	🛅	1.0	left luggage	baggage|case|locker		
symbols	🛜	15.0	wireless	broadband|computer|connectivity|hotspot|internet|network|router|smartphone|wi-fi|wifi|wlan		
symbols	🚹	0.6	men’s room	bathroom|lavatory|man|restroom|toilet|wc		
symbols	🚺	0.6	women’s room	bathroom|lavatory|restroom|toilet|wc|woman		
symbols	🚼	0.6	baby symbol	changing		
symbols	🧑‍🧑‍🧒	15.1	family: adult, adult, child			
symbols	🧑‍🧑‍🧒‍🧒	15.1	family: adult, adult, child, child			
symbols	🧑‍🧒	15.1	family: adult, child			
symbols	🧑‍🧒‍🧒	15.1	family: adult, child, child			
symbols	⚧️	13.0	transgender symbol			
symbols	🚻	0.6	restroom	bathroom|lavatory|toilet|wc		
symbols	🚮	1.0	litter in bin sign	litterbin		
symbols	🎦	0.6	cinema	camera|film|movie		
symbols	📶	0.6	antenna bars	bar|cell|communication|mobile|phone|signal|telephone		
symbols	🈁	0.6	Japanese “here” button	katakana		
symbols	🔣	0.6	input symbols			
symbols	ℹ️	0.6	information	i		
symbols	🔤	0.6	input latin letters	abc|alphabet		
symbols	🔡	0.6	input latin lowercase	abcd|letters		
symbols	🔠	0.6	input latin uppercase	abcd|letters		
symbols	🆖	0.6	NG button			
symbols	🆗	0.6	OK button	okay		
symbols	🆙	0.6	UP! button	mark		
symbols	🆒	0.6	COOL button			
symbols	🆕	0.6	NEW button			
symbols	🆓	0.6	FREE button			
symbols	0️⃣	0.6	keycap: 0	zero		
symbols	1️⃣	0.6	keycap: 1	one		
symbols	2️⃣	0.6	keycap: 2	two		
symbols	3️⃣	0.6	keycap: 3	three		
symbols	4️⃣	0.6	keycap: 4	four		
symbols	5️⃣	0.6	keycap: 5	five		
symbols	6️⃣	0.6	keycap: 6	six		
symbols	7️⃣	0.6	keycap: 7	seven		
symbols	8️⃣	0.6	keycap: 8	eight		
symbols	9️⃣	0.6	keycap: 9	nine		
symbols	🔟	0.6	keycap: 10			
symbols	🔢	0.6	input numbers	1234		
symbols	#️⃣	0.6	keycap: #			
symbols	*️⃣	2.0	keycap: *			
symbols	⏏️	1.0	eject button			
symbols	▶️	0.6	play button	arrow|right|triangle		
symbols	⏸️	0.7	pause button	bar|double|vertical		
symbols	⏯️	1.0	play or pause button	arrow|right|triangle		
symbols	⏹️	0.7	stop button	square		
symbols	⏺️	0.7	record button	circle		
symbols	⏭️	0.7	next track button	arrow|scene|triangle		
symbols	⏮️	0.7	last track button	arrow|previous|scene|triangle		
symbols	⏩️	0.6	fast-forward button	arrow|double		
symbols	⏪️	0.6	fast reverse button	arrow|double|rewind		
symbols	⏫️	0.6	fast up button	arrow|double		
symbols	⏬️	0.6	fast down button	arrow|double		
symbols	◀️	0.6	reverse button	arrow|left|triangle		
symbols	🔼	0.6	upwards button	arrow|red|up		
symbols	🔽	0.6	downwards button	arrow|down|red		
symbols	➡️	0.6	right arrow	cardinal|direction|east		
symbols	⬅️	0.6	left arrow	cardinal|direction|west		
symbols	⬆️	0.6	up arrow	cardinal|direction|north		
symbols	⬇️	0.6	down arrow	cardinal|direction|south		
symbols	↗️	0.6	up-right arrow	direction|intercardinal|northeast		
symbols	↘️	0.6	down-right arrow	direction|intercardinal|southeast		
symbols	↙️	0.6	down-left arrow	direction|intercardinal|southwest		
symbols	↖️	0.6	up-left arrow	direction|intercardinal|northwest		
symbols	↕️	0.6	up-down arrow			
symbols	↔️	0.6	left-right arrow			
symbols	↪️	0.6	left arrow curving right			
symbols	↩️	0.6	right arrow curving left			
symbols	⤴️	0.6	right arrow curving up			
symbols	⤵️	0.6	right arrow curving down			
symbols	🔀	1.0	shuffle tracks button	arrow|crossed		
symbols	🔁	1.0	repeat button	arrow|clockwise		
symbols	🔂	1.0	repeat single button	arrow|clockwise|once		
symbols	🔄	1.0	counterclockwise arrows button	again|anticlockwise|arrow|deja|refresh|rewindershins|vu		
symbols	🔃	0.6	clockwise vertical arrows	arrow|refresh|reload		
symbols	🎵	0.6	musical note	music|sound		
symbols	🎶	0.6	musical notes	music|note|sound		
symbols	➕	0.6	plus			
symbols	➖	0.6	minus	heavy|math|sign		
symbols	➗	0.6	divide	division|heavy|math|sign		
symbols	✖️	0.6	multiply	cancel|multiplication|sign|x		
symbols	🟰	14.0	heavy equals sign	answer|equal|equality|math		
symbols	♾️	11.0	infinity	forever|unbounded|universal		
symbols	💲	0.6	heavy dollar sign	billion|cash|charge|currency|million|money|pay		
symbols	💱	0.6	currency exchange	bank|money		
symbols	™️	0.6	trade mark	tm|trademark		
symbols	©️	0.6	copyright	c		
symbols	®️	0.6	registered	r		
symbols	👁️‍🗨️	2.0	eye in speech bubble	balloon|witness		
symbols	🔚	0.6	END arrow			
symbols	🔙	0.6	BACK arrow			
symbols	🔛	0.6	ON! arrow	mark		
symbols	🔝	0.6	TOP arrow	homie|up		
symbols	🔜	0.6	SOON arrow	brb|omw		
symbols	〰️	0.6	wavy dash	punctuation		
symbols	➰	0.6	curly loop	curl		
symbols	➿	1.0	double curly loop	curl		
symbols	✔️	0.6	check mark	checked|checkmark|done|heavy|tick		
symbols	☑️	0.6	check box with check	ballot|checked|done|off|tick		
symbols	🔘	0.6	radio button	geometric		
symbols	🔴	0.6	red circle	geometric		
symbols	🟠	12.0	orange circle			
symbols	🟡	12.0	yellow circle			
symbols	🟢	12.0	green circle			
symbols	🔵	0.6	blue circle	geometric		
symbols	🟣	12.0	purple circle			
symbols	⚫️	0.6	black circle	geometric		
symbols	⚪️	0.6	white circle	geometric		
symbols	🟤	12.0	brown circle			
symbols	🔺	0.6	red triangle pointed up	geometric		
symbols	🔻	0.6	red triangle pointed down	geometric		
symbols	🔸	0.6	small orange diamond	geometric		
symbols	🔹	0.6	small blue diamond	geometric		
symbols	🔶	0.6	large orange diamond	geometric		
symbols	🔷	0.6	large blue diamond	geometric		
symbols	🔳	0.6	white square button	geometric|outlined		
symbols	🔲	0.6	black square button	geometric		
symbols	▪️	0.6	black small square	geometric		
symbols	▫️	0.6	white small square	geometric		
symbols	◾️	0.6	black medium-small square	geometric		
symbols	◽️	0.6	white medium-small square	geometric		
symbols	◼️	0.6	black medium square	geometric		
symbols	◻️	0.6	white medium square	geometric		
symbols	🟥	12.0	red square	card|penalty		
symbols	🟧	12.0	orange square			
symbols	🟨	12.0	yellow square	card|penalty		
symbols	🟩	12.0	green square			
symbols	🟦	12.0	blue square			
symbols	🟪	12.0	purple square			
symbols	⬛️	0.6	black large square	geometric		
symbols	⬜️	0.6	white large square	geometric		
symbols	🟫	12.0	brown square			
symbols	🔈	0.7	speaker low volume	soft|sound		
symbols	🔇	1.0	muted speaker	mute|quiet|silent|sound		
symbols	🔉	1.0	speaker medium volume	sound		
symbols	🔊	0.6	speaker high volume	loud|music|sound		
symbols	🔔	0.6	bell	break|church|sound		
symbols	🔕	1.0	bell with slash	forbidden|mute|no|not|prohibited|quiet|silent|sound		
symbols	📣	0.6	megaphone	cheering|sound		
symbols	📢	0.6	loudspeaker	address|communication|loud|public|sound		
symbols	💬	0.6	speech balloon	bubble|comic|dialog|message|sms|talk|text|typing		
symbols	💭	1.0	thought balloon	bubble|cartoon|cloud|comic|daydream|decisions|dream|idea|invent|invention|realize|think|thoughts|wonder		
symbols	🗯️	0.7	right anger bubble	angry|balloon|mad		
symbols	♠️	0.6	spade suit	card|game		
symbols	♣️	0.6	club suit	card|clubs|game		
symbols	♥️	0.6	heart suit	card|emotion|game|hearts		
symbols	♦️	0.6	diamond suit	card|game		
symbols	🃏	0.6	joker	card|game|wildcard		
symbols	🎴	0.6	flower playing cards	card|game|japanese		
symbols	🀄️	0.6	mahjong red dragon	game		
symbols	🕐	0.6	one o’clock	1|1:00|time		
symbols	🕑	0.6	two o’clock	2|2:00|time		
symbols	🕒	0.6	three o’clock	3|3:00|time		
symbols	🕓	0.6	four o’clock	4|4:00|time		
symbols	🕔	0.6	five o’clock	5|5:00|time		
symbols	🕕	0.6	six o’clock	6|6:00|time		
symbols	🕖	0.6	seven o’clock	0|7|7:00		
symbols	🕗	0.6	eight o’clock	8|8:00|time		
symbols	🕘	0.6	nine o’clock	9|9:00|time		
symbols	🕙	0.6	ten o’clock	0|10|10:00		
symbols	🕚	0.6	eleven o’clock	11|11:00|time		
symbols	🕛	0.6	twelve o’clock	12|12:00|time		
symbols	🕜	0.7	one-thirty	1|1:30|30|clock|time		
symbols	🕝	0.7	two-thirty	2|2:30|30|clock|time		
symbols	🕞	0.7	three-thirty	3|3:30|30|clock|time		
symbols	🕟	0.7	four-thirty	30|4|4:30|clock|time		
symbols	🕠	0.7	five-thirty	30|5|5:30|clock|time		
symbols	🕡	0.7	six-thirty	30|6|6:30|clock		
symbols	🕢	0.7	seven-thirty	30|7|7:30|clock		
symbols	🕣	0.7	eight-thirty	30|8|8:30|clock|time		
symbols	🕤	0.7	nine-thirty	30|9|9:30|clock|time		
symbols	🕥	0.7	ten-thirty	10|10:30|30|clock|time		
symbols	🕦	0.7	eleven-thirty	11|11:30|30|clock|time		
symbols	🕧	0.7	twelve-thirty	12|12:30|30|clock|time		
flags	🏳️	0.7	white flag	waving		
flags	🏴	1.0	black flag	waving		
flags	🏴‍☠️	11.0	pirate flag	jolly|plunder|roger|treasure		
flags	🏁	0.6	chequered flag	checkered|finish|flags|game|race|racing|sport|win		
flags	🚩	0.6	triangular flag	construction|golf|post		
flags	🏳️‍🌈	4.0	rainbow flag	bisexual|gay|genderqueer|glbt|glbtq|lesbian|lgbt|lgbtq|lgbtqia|pride|queer|trans|transgender		
flags	🏳️‍⚧️	13.0	transgender flag	blue|light|pink|white		
flags	🇺🇳	4.0	flag: United Nations			
flags	🇦🇫	2.0	flag: Afghanistan			
flags	🇦🇽	2.0	flag: Åland Islands			
flags	🇦🇱	2.0	flag: Albania			
flags	🇩🇿	2.0	flag: Algeria			
flags	🇦🇸	2.0	flag: American Samoa			
flags	🇦🇩	2.0	flag: Andorra			
flags	🇦🇴	2.0	flag: Angola			
flags	🇦🇮	2.0	flag: Anguilla			
flags	🇦🇶	2.0	flag: Antarctica			
flags	🇦🇬	2.0	flag: Antigua & Barbuda			
flags	🇦🇷	2.0	flag: Argentina			
flags	🇦🇲	2.0	flag: Armenia			
flags	🇦🇼	2.0	flag: Aruba			
flags	🇦🇺	2.0	flag: Australia			
flags	🇦🇹	2.0	flag: Austria			
flags	🇦🇿	2.0	flag: Azerbaijan			
flags	🇧🇸	2.0	flag: Bahamas			
flags	🇧🇭	2.0	flag: Bahrain			
flags	🇧🇩	2.0	flag: Bangladesh			
flags	🇧🇧	2.0	flag: Barbados			
flags	🇧🇾	2.0	flag: Belarus			
flags	🇧🇪	2.0	flag: Belgium			
flags	🇧🇿	2.0	flag: Belize			
flags	🇧🇯	2.0	flag: Benin			
flags	🇧🇲	2.0	flag: Bermuda			
flags	🇧🇹	2.0	flag: Bhutan			
flags	🇧🇴	2.0	flag: Bolivia			
flags	🇧🇦	2.0	flag: Bosnia & Herzegovina			
flags	🇧🇼	2.0	flag: Botswana			
flags	🇧🇷	2.0	flag: Brazil			
flags	🇻🇬	2.0	flag: British Virgin Islands			
flags	🇧🇳	2.0	flag: Brunei			
flags	🇧🇬	2.0	flag: Bulgaria			
flags	🇧🇫	2.0	flag: Burkina Faso			
flags	🇧🇮	2.0	flag: Burundi			
flags	🇰🇭	2.0	flag: Cambodia			
flags	🇨🇲	2.0	flag: Cameroon			
flags	🇨🇦	2.0	flag: Canada			
flags	🇮🇨	2.0	flag: Canary Islands			
flags	🇨🇻	2.0	flag: Cape Verde			
flags	🇧🇶	2.0	flag: Caribbean Netherlands			
flags	🇰🇾	2.0	flag: Cayman Islands			
flags	🇨🇫	2.0	flag: Central African Republic			
flags	🇹🇩	2.0	flag: Chad			
flags	🇮🇴	2.0	flag: British Indian Ocean Territory			
flags	🇨🇱	2.0	flag: Chile			
flags	🇨🇳	0.6	flag: China			
flags	🇨🇽	2.0	flag: Christmas Island			
flags	🇨🇨	2.0	flag: Cocos (Keeling) Islands			
flags	🇨🇴	2.0	flag: Colombia			
flags	🇰🇲	2.0	flag: Comoros			
flags	🇨🇬	2.0	flag: Congo - Brazzaville			
flags	🇨🇩	2.0	flag: Congo - Kinshasa			
flags	🇨🇰	2.0	flag: Cook Islands			
flags	🇨🇷	2.0	flag: Costa Rica			
flags	🇨🇮	2.0	flag: Côte d’Ivoire			
flags	🇭🇷	2.0	flag: Croatia			
flags	🇨🇺	2.0	flag: Cuba			
flags	🇨🇼	2.0	flag: Curaçao			
flags	🇨🇾	2.0	flag: Cyprus			
flags	🇨🇿	2.0	flag: Czechia			
flags	🇩🇰	2.0	flag: Denmark			
flags	🇩🇯	2.0	flag: Djibouti			
flags	🇩🇲	2.0	flag: Dominica			
flags	🇩🇴	2.0	flag: Dominican Republic			
flags	🇪🇨	2.0	flag: Ecuador			
flags	🇪🇬	2.0	flag: Egypt			
flags	🇸🇻	2.0	flag: El Salvador			
flags	🇬🇶	2.0	flag: Equatorial Guinea			
flags	🇪🇷	2.0	flag: Eritrea			
flags	🇪🇪	2.0	flag: Estonia			
flags	🇸🇿	2.0	flag: Eswatini			
flags	🇪🇹	2.0	flag: Ethiopia			
flags	🇪🇺	2.0	flag: European Union			
flags	🇫🇰	2.0	flag: Falkland Islands			
flags	🇫🇴	2.0	flag: Faroe Islands			
flags	🇫🇯	2.0	flag: Fiji			
flags	🇫🇮	2.0	flag: Finland			
flags	🇫🇷	0.6	flag: France			
flags	🇬🇫	2.0	flag: French Guiana			
flags	🇵🇫	2.0	flag: French Polynesia			
flags	🇹🇫	2.0	flag: French Southern Territories			
flags	🇬🇦	2.0	flag: Gabon			
flags	🇬🇲	2.0	flag: Gambia			
flags	🇬🇪	2.0	flag: Georgia			
flags	🇩🇪	0.6	flag: Germany			
flags	🇬🇭	2.0	flag: Ghana			
flags	🇬🇮	2.0	flag: Gibraltar			
flags	🇬🇷	2.0	flag: Greece			
flags	🇬🇱	2.0	flag: Greenland			
flags	🇬🇩	2.0	flag: Grenada			
flags	🇬🇵	2.0	flag: Guadeloupe			
flags	🇬🇺	2.0	flag: Guam			
flags	🇬🇹	2.0	flag: Guatemala			
flags	🇬🇬	2.0	flag: Guernsey			
flags	🇬🇳	2.0	flag: Guinea			
flags	🇬🇼	2.0	flag: Guinea-Bissau			
flags	🇬🇾	2.0	flag: Guyana			
flags	🇭🇹	2.0	flag: Haiti			
flags	🇭🇳	2.0	flag: Honduras			
flags	🇭🇰	2.0	flag: Hong Kong SAR China			
flags	🇭🇺	2.0	flag: Hungary			
flags	🇮🇸	2.0	flag: Iceland			
flags	🇮🇳	2.0	flag: India			
flags	🇮🇩	2.0	flag: Indonesia			
flags	🇮🇷	2.0	flag: Iran			
flags	🇮🇶	2.0	flag: Iraq			
flags	🇮🇪	2.0	flag: Ireland			
flags	🇮🇲	2.0	flag: Isle of Man			
flags	🇮🇱	2.0	flag: Israel			
flags	🇮🇹	0.6	flag: Italy			
flags	🇯🇲	2.0	flag: Jamaica			
flags	🇯🇵	0.6	flag: Japan			
flags	🎌	0.6	crossed flags	celebration|cross|japanese		
flags	🇯🇪	2.0	flag: Jersey			
flags	🇯🇴	2.0	flag: Jordan			
flags	🇰🇿	2.0	flag: Kazakhstan			
flags	🇰🇪	2.0	flag: Kenya			
flags	🇰🇮	2.0	flag: Kiribati			
flags	🇽🇰	2.0	flag: Kosovo			
flags	🇰🇼	2.0	flag: Kuwait			
flags	🇰🇬	2.0	flag: Kyrgyzstan			
flags	🇱🇦	2.0	flag: Laos			
flags	🇱🇻	2.0	flag: Latvia			
flags	🇱🇧	2.0	flag: Lebanon			
flags	🇱🇸	2.0	flag: Lesotho			
flags	🇱🇷	2.0	flag: Liberia			
flags	🇱🇾	2.0	flag: Libya			
flags	🇱🇮	2.0	flag: Liechtenstein			
flags	🇱🇹	2.0	flag: Lithuania			
flags	🇱🇺	2.0	flag: Luxembourg			
flags	🇲🇴	2.0	flag: Macao SAR China			
flags	🇲🇬	2.0	flag: Madagascar			
flags	🇲🇼	2.0	flag: Malawi			
flags	🇲🇾	2.0	flag: Malaysia			
flags	🇲🇻	2.0	flag: Maldives			
flags	🇲🇱	2.0	flag: Mali			
flags	🇲🇹	2.0	flag: Malta			
flags	🇲🇭	2.0	flag: Marshall Islands			
flags	🇲🇶	2.0	flag: Martinique			
flags	🇲🇷	2.0	flag: Mauritania			
flags	🇲🇺	2.0	flag: Mauritius			
flags	🇾🇹	2.0	flag: Mayotte			
flags	🇲🇽	2.0	flag: Mexico			
flags	🇫🇲	2.0	flag: Micronesia			
flags	🇲🇩	2.0	flag: Moldova			
flags	🇲🇨	2.0	flag: Monaco			
flags	🇲🇳	2.0	flag: Mongolia			
flags	🇲🇪	2.0	flag: Montenegro			
flags	🇲🇸	2.0	flag: Montserrat			
flags	🇲🇦	2.0	flag: Morocco			
flags	🇲🇿	2.0	flag: Mozambique			
flags	🇲🇲	2.0	flag: Myanmar (Burma)			
flags	🇳🇦	2.0	flag: Namibia			
flags	🇳🇷	2.0	flag: Nauru			
flags	🇳🇵	2.0	flag: Nepal			
flags	🇳🇱	2.0	flag: Netherlands			
flags	🇳🇨	2.0	flag: New Caledonia			
flags	🇳🇿	2.0	flag: New Zealand			
flags	🇳🇮	2.0	flag: Nicaragua			
flags	🇳🇪	2.0	flag: Niger			
flags	🇳🇬	2.0	flag: Nigeria			
flags	🇳🇺	2.0	flag: Niue			
flags	🇳🇫	2.0	flag: Norfolk Island			
flags	🇰🇵	2.0	flag: North Korea			
flags	🇲🇰	2.0	flag: North Macedonia			
flags	🇲🇵	2.0	flag: Northern Mariana Islands			
flags	🇳🇴	2.0	flag: Norway			
flags	🇴🇲	2.0	flag: Oman			
flags	🇵🇰	2.0	flag: Pakistan			
flags	🇵🇼	2.0	flag: Palau			
flags	🇵🇸	2.0	flag: Palestinian Territories			
flags	🇵🇦	2.0	flag: Panama			
flags	🇵🇬	2.0	flag: Papua New Guinea			
flags	🇵🇾	2.0	flag: Paraguay			
flags	🇵🇪	2.0	flag: Peru			
flags	🇵🇭	2.0	flag: Philippines			
flags	🇵🇳	2.0	flag: Pitcairn Islands			
flags	🇵🇱	2.0	flag: Poland			
flags	🇵🇹	2.0	flag: Portugal			
flags	🇵🇷	2.0	flag: Puerto Rico			
flags	🇶🇦	2.0	flag: Qatar			
flags	🇷🇪	2.0	flag: Réunion			
flags	🇷🇴	2.0	flag: Romania			
flags	🇷🇺	0.6	flag: Russia			
flags	🇷🇼	2.0	flag: Rwanda			
flags	🇼🇸	2.0	flag: Samoa			
flags	🇸🇲	2.0	flag: San Marino			
flags	🇸🇹	2.0	flag: São Tomé & Príncipe			
flags	🇨🇶	16.0	flag: Sark			
flags	🇸🇦	2.0	flag: Saudi Arabia			
flags	🇸🇳	2.0	flag: Senegal			
flags	🇷🇸	2.0	flag: Serbia			
flags	🇸🇨	2.0	flag: Seychelles			
flags	🇸🇱	2.0	flag: Sierra Leone			
flags	🇸🇬	2.0	flag: Singapore			
flags	🇸🇽	2.0	flag: Sint Maarten			
flags	🇸🇰	2.0	flag: Slovakia			
flags	🇸🇮	2.0	flag: Slovenia			
flags	🇬🇸	2.0	flag: South Georgia & South Sandwich Islands			
flags	🇸🇧	2.0	flag: Solomon Islands			
flags	🇸🇴	2.0	flag: Somalia			
flags	🇿🇦	2.0	flag: South Africa			
flags	🇰🇷	0.6	flag: South Korea			
flags	🇸🇸	2.0	flag: South Sudan			
flags	🇪🇸	0.6	flag: Spain			
flags	🇱🇰	2.0	flag: Sri Lanka			
flags	🇧🇱	2.0	flag: St. Barthélemy			
flags	🇸🇭	2.0	flag: St. Helena			
flags	🇰🇳	2.0	flag: St. Kitts & Nevis			
flags	🇱🇨	2.0	flag: St. Lucia			
flags	🇵🇲	2.0	flag: St. Pierre & Miquelon			
flags	🇻🇨	2.0	flag: St. Vincent & Grenadines			
flags	🇸🇩	2.0	flag: Sudan			
flags	🇸🇷	2.0	flag: Suriname			
flags	🇸🇪	2.0	flag: Sweden			
flags	🇨🇭	2.0	flag: Switzerland			
flags	🇸🇾	2.0	flag: Syria			
flags	🇹🇼	2.0	flag: Taiwan			
flags	🇹🇯	2.0	flag: Tajikistan			
flags	🇹🇿	2.0	flag: Tanzania			
flags	🇹🇭	2.0	flag: Thailand			
flags	🇹🇱	2.0	flag: Timor-Leste			
flags	🇹🇬	2.0	flag: Togo			
flags	🇹🇰	2.0	flag: Tokelau			
flags	🇹🇴	2.0	flag: Tonga			
flags	🇹🇹	2.0	flag: Trinidad & Tobago			
flags	🇹🇳	2.0	flag: Tunisia			
flags	🇹🇷	2.0	flag: Türkiye			
flags	🇹🇲	2.0	flag: Turkmenistan			
flags	🇹🇨	2.0	flag: Turks & Caicos Islands			
flags	🇹🇻	2.0	flag: Tuvalu			
flags	🇻🇮	2.0	flag: U.S. Virgin Islands			
flags	🇺🇬	2.0	flag: Uganda			
flags	🇺🇦	2.0	flag: Ukraine			
flags	🇦🇪	2.0	flag: United Arab Emirates			
flags	🇬🇧	0.6	flag: United Kingdom			
flags	🏴󠁧󠁢󠁥󠁮󠁧󠁿	5.0	flag: England			
flags	🏴󠁧󠁢󠁳󠁣󠁴󠁿	5.0	flag: Scotland			
flags	🏴󠁧󠁢󠁷󠁬󠁳󠁿	5.0	flag: Wales			
flags	🇺🇸	0.6	flag: United States			
flags	🇺🇾	2.0	flag: Uruguay			
flags	🇺🇿	2.0	flag: Uzbekistan			
flags	🇻🇺	2.0	flag: Vanuatu			
flags	🇻🇦	2.0	flag: Vatican City			
flags	🇻🇪	2.0	flag: Venezuela			
flags	🇻🇳	2.0	flag: Vietnam			
flags	🇼🇫	2.0	flag: Wallis & Futuna			
flags	🇪🇭	2.0	flag: Western Sahara			
flags	🇾🇪	2.0	flag: Yemen			
flags	🇿🇲	2.0	flag: Zambia			
flags	🇿🇼	2.0	flag: Zimbabwe			
"""#
    // END GENERATED
}
