import Foundation

/// Curated emoji set (§6.1: recents, search, skin tones). Deliberately compact
/// — static string literals only; the full Unicode name table costs memory the
/// extension doesn't have. Search covers the common-name map below.
enum EmojiData {

    /// Apple's emoji keyboard has nine tabs: Frequently Used, Smileys &
    /// People, Animals & Nature, Food & Drink, Activity, Travel & Places,
    /// Objects, Symbols and Flags. The lists below are kept by theme; the
    /// board shows them in Apple's order and with Apple-like tab glyphs.
    static let categories: [(id: String, symbol: String, emoji: [String])] = {
        let byId = Dictionary(uniqueKeysWithValues: raw.map { ($0.id, $0.emoji) })
        func list(_ id: String) -> [String] { byId[id] ?? [] }
        return [
            ("smileys", "face.smiling", list("smileys") + list("people")),
            ("animals", "teddybear", list("animals")),
            ("food", "takeoutbag.and.cup.and.straw", list("food")),
            ("activity", "soccerball", list("activity")),
            ("travel", "car", list("travel")),
            ("objects", "lightbulb", list("objects")),
            ("symbols", "heart", list("symbols")),
            ("flags", "flag", flags),
        ]
    }()

    /// Country flags from their ISO codes (two regional-indicator letters
    /// each), alphabetical by English name as Apple lists them, after the
    /// handful of flags that are not countries.
    static let flags: [String] = {
        let codes = """
        AF AL DZ AR AM AU AT AZ BH BD BE BT BO BA BR BG KH CA CL CN CO CR HR CU CY \
        CZ DK DO EC EG SV EE ET FI FR GE DE GH GR GT HN HK HU IS IN ID IR IQ IE IL \
        IT JM JP JO KZ KE KW LA LV LB LT LU MY MV MT MX MN MA MM NP NL NZ NG NO OM \
        PK PA PY PE PH PL PT QA RO RU SA RS SG SK SI ZA KR ES LK SE CH TW TZ TH TR \
        UG UA AE GB US UY UZ VE VN YE ZM ZW
        """
        let country = codes.split(separator: " ").compactMap { code -> String? in
            let scalars = code.unicodeScalars.compactMap {
                Unicode.Scalar(0x1F1E6 + $0.value - 65)
            }
            guard scalars.count == 2 else { return nil }
            return String(String.UnicodeScalarView(scalars))
        }
        return ["🏁", "🚩", "🎌", "🏴", "🏳️", "🏳️‍🌈", "🏳️‍⚧️", "🏴‍☠️", "🇺🇳"] + country
    }()

    private static let raw: [(id: String, emoji: [String])] = [
        ("smileys", [
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥲", "☺️", "😊", "😇", "🙂", "🙃", "😉",
            "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓",
            "😎", "🥸", "🤩", "🥳", "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣", "😖", "😫",
            "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰",
            "😥", "😓", "🤗", "🤔", "🫡", "🤭", "🫢", "🤫", "😶", "🫥", "😐", "😑", "😬", "🙄", "😯",
            "😴", "🤤", "😪", "😮‍💨", "🤢", "🤮", "🤧", "😷", "🤒", "🤕", "🤑", "🤠", "😈", "👿", "🤡",
            "💀", "☠️", "👻", "👽", "🤖", "💩", "🔥", "✨", "💫", "💯", "💢", "💥", "💦", "💤",
        ]),
        ("people", [
            "👋", "🤚", "🖐️", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🫰", "🤟", "🤘", "🤙", "👈",
            "👉", "👆", "👇", "☝️", "👍", "👎", "✊", "👊", "🤛", "🤜", "👏", "🙌", "🫶", "👐", "🤲",
            "🤝", "🙏", "✍️", "💅", "🤳", "💪", "🦾", "🧠", "👀", "👁️", "👄", "🫦", "👶", "🧒", "👦",
            "👧", "🧑", "👨", "👩", "🧔", "👱", "🧓", "👴", "👵", "🙍", "🙎", "🙅", "🙆", "💁", "🙋",
            "🧏", "🙇", "🤦", "🤷", "👮", "🕵️", "💂", "👷", "🫅", "🤴", "👸", "👳", "👲", "🧕", "🤵",
            "👰", "🤰", "🤱", "👼", "🎅", "🤶", "🦸", "🦹", "🧙", "🧚", "🧛", "🧜", "🧝", "🧞", "🧟",
        ]),
        ("animals", [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸",
            "🐵", "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤", "🐣", "🦆", "🦅", "🦉", "🦇", "🐺",
            "🐗", "🐴", "🦄", "🐝", "🪱", "🐛", "🦋", "🐌", "🐞", "🐜", "🦟", "🦗", "🕷️", "🦂", "🐢",
            "🐍", "🦎", "🦖", "🦕", "🐙", "🦑", "🦐", "🦞", "🦀", "🐡", "🐠", "🐟", "🐬", "🐳", "🐋",
            "🦈", "🐊", "🐅", "🐆", "🦓", "🦍", "🦧", "🐘", "🦛", "🦏", "🐪", "🐫", "🦒", "🦘", "🐃",
        ]),
        ("food", [
            "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍",
            "🥥", "🥝", "🍅", "🍆", "🥑", "🥦", "🥬", "🥒", "🌶️", "🫑", "🌽", "🥕", "🫒", "🧄", "🧅",
            "🥔", "🍠", "🥐", "🥯", "🍞", "🥖", "🥨", "🧀", "🥚", "🍳", "🧈", "🥞", "🧇", "🥓", "🥩",
            "🍗", "🍖", "🌭", "🍔", "🍟", "🍕", "🫓", "🥪", "🥙", "🧆", "🌮", "🌯", "🫔", "🥗", "🥘",
            "🍝", "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🦪", "🍤", "🍙", "🍚", "🍘", "🍥", "🥠", "🍢",
            "🍡", "🍧", "🍨", "🍦", "🥧", "🧁", "🍰", "🎂", "🍮", "🍭", "🍬", "🍫", "🍿", "🍩", "🍪",
            "☕", "🍵", "🧋", "🥤", "🧃", "🍺", "🍻", "🥂", "🍷", "🥃", "🍸", "🍹", "🍾",
        ]),
        ("activity", [
            "⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🪀", "🏓", "🏸", "🏒", "🏑",
            "🥍", "🏏", "🪃", "🥅", "⛳", "🪁", "🏹", "🎣", "🤿", "🥊", "🥋", "🎽", "🛹", "🛼", "🛷",
            "⛸️", "🥌", "🎿", "⛷️", "🏂", "🏋️", "🤼", "🤸", "⛹️", "🤺", "🤾", "🏌️", "🏇", "🧘", "🏄",
            "🏊", "🤽", "🚣", "🧗", "🚵", "🚴", "🏆", "🥇", "🥈", "🥉", "🏅", "🎖️", "🎗️", "🎫", "🎟️",
            "🎪", "🤹", "🎭", "🩰", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🪘", "🎷", "🎺", "🪗",
            "🎸", "🪕", "🎻", "🎲", "♟️", "🎯", "🎳", "🎮", "🎰", "🧩",
        ]),
        ("travel", [
            "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐", "🛻", "🚚", "🚛", "🚜", "🦯",
            "🦽", "🦼", "🛴", "🚲", "🛵", "🏍️", "🛺", "🚨", "🚔", "🚍", "🚘", "🚖", "🚡", "🚠", "🚟",
            "🚃", "🚋", "🚞", "🚝", "🚄", "🚅", "🚈", "🚂", "🚆", "🚇", "🚊", "🚉", "✈️", "🛫", "🛬",
            "🛩️", "💺", "🛰️", "🚀", "🛸", "🚁", "🛶", "⛵", "🚤", "🛥️", "🛳️", "⛴️", "🚢", "⚓", "🪝",
            "⛽", "🚧", "🚦", "🚥", "🗺️", "🗿", "🗽", "🗼", "🏰", "🏯", "🏟️", "🎡", "🎢", "🎠", "⛲",
            "⛱️", "🏖️", "🏝️", "🏜️", "🌋", "⛰️", "🏔️", "🗻", "🏕️", "⛺", "🛖", "🏠", "🏡", "🏘️", "🏚️",
        ]),
        ("objects", [
            "⌚", "📱", "📲", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "🖲️", "🕹️", "🗜️", "💽", "💾", "💿", "📀",
            "📼", "📷", "📸", "📹", "🎥", "📽️", "🎞️", "📞", "☎️", "📟", "📠", "📺", "📻", "🎙️", "🎚️",
            "🎛️", "🧭", "⏱️", "⏲️", "⏰", "🕰️", "⌛", "⏳", "📡", "🔋", "🪫", "🔌", "💡", "🔦", "🕯️",
            "🪔", "🧯", "🛢️", "💸", "💵", "💴", "💶", "💷", "🪙", "💰", "💳", "💎", "⚖️", "🪜", "🧰",
            "🪛", "🔧", "🔨", "⚒️", "🛠️", "⛏️", "🪚", "🔩", "⚙️", "🪤", "🧱", "⛓️", "🧲", "🔫", "💣",
            "🧨", "🪓", "🔪", "🗡️", "⚔️", "🛡️", "🚬", "⚰️", "🪦", "⚱️", "🏺", "🔮", "📿", "🧿", "💈",
        ]),
        ("symbols", [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❤️‍🔥", "❤️‍🩹", "❣️", "💕", "💞",
            "💓", "💗", "💖", "💘", "💝", "💟", "☮️", "✝️", "☪️", "🕉️", "☸️", "✡️", "🔯", "🕎", "☯️",
            "☦️", "🛐", "⛎", "♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓",
            "🆔", "⚛️", "✅", "☑️", "✔️", "❌", "❎", "➕", "➖", "➗", "✖️", "🟰", "💲", "💱", "™️",
            "©️", "®️", "〰️", "➰", "➿", "🔚", "🔙", "🔛", "🔝", "🔜", "⚠️", "🚸", "🔱", "⚜️", "🔰",
            "♻️", "🈯", "💹", "❇️", "✳️", "❎", "🌐", "💠", "Ⓜ️", "🌀", "💤", "🏧", "🚾", "♿", "🅿️",
        ]),
    ]

    /// Bases that accept Fitzpatrick skin-tone modifiers via simple append.
    static let skinToneBases: Set<String> = [
        "👋", "🤚", "🖐️", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🫰", "🤟", "🤘", "🤙", "👈",
        "👉", "👆", "👇", "☝️", "👍", "👎", "✊", "👊", "🤛", "🤜", "👏", "🙌", "🫶", "👐", "🤲",
        "🙏", "✍️", "💅", "🤳", "💪", "👶", "🧒", "👦", "👧", "🧑", "👨", "👩", "🧓", "👴", "👵",
        "🙋", "🙇", "🤦", "🤷", "🎅", "🤶", "💁", "🙅", "🙆",
    ]

    static let skinTones = ["🏻", "🏼", "🏽", "🏾", "🏿"]

    static func variants(of base: String) -> [String] {
        guard skinToneBases.contains(base) else { return [base] }
        // Strip VS16 before appending a tone modifier so ✌️ becomes ✌🏽.
        let stripped = base.replacingOccurrences(of: "\u{FE0F}", with: "")
        return [base] + skinTones.map { stripped + $0 }
    }

    /// Small common-name index for search (§6.1). name → emoji.
    static let names: [(String, String)] = [
        ("laugh", "😂"), ("joy", "😂"), ("rofl", "🤣"), ("smile", "😄"), ("happy", "😊"),
        ("grin", "😁"), ("wink", "😉"), ("love", "😍"), ("heart eyes", "😍"), ("kiss", "😘"),
        ("cool", "😎"), ("party", "🥳"), ("smirk", "😏"), ("sad", "😢"), ("cry", "😭"),
        ("angry", "😡"), ("rage", "🤬"), ("mind blown", "🤯"), ("shock", "😱"), ("think", "🤔"),
        ("hug", "🤗"), ("shush", "🤫"), ("sleep", "😴"), ("sick", "🤒"), ("mask", "😷"),
        ("devil", "😈"), ("clown", "🤡"), ("skull", "💀"), ("ghost", "👻"), ("alien", "👽"),
        ("robot", "🤖"), ("poop", "💩"), ("fire", "🔥"), ("sparkle", "✨"), ("hundred", "💯"),
        ("wave", "👋"), ("ok", "👌"), ("peace", "✌️"), ("crossed", "🤞"), ("rock", "🤘"),
        ("call", "🤙"), ("point", "👉"), ("up", "👍"), ("thumbs up", "👍"), ("down", "👎"),
        ("thumbs down", "👎"), ("fist", "✊"), ("punch", "👊"), ("clap", "👏"), ("raise", "🙌"),
        ("pray", "🙏"), ("thanks", "🙏"), ("muscle", "💪"), ("flex", "💪"), ("eyes", "👀"),
        ("brain", "🧠"), ("shrug", "🤷"), ("facepalm", "🤦"), ("dog", "🐶"), ("cat", "🐱"),
        ("fox", "🦊"), ("bear", "🐻"), ("panda", "🐼"), ("lion", "🦁"), ("pig", "🐷"),
        ("monkey", "🐵"), ("chicken", "🐔"), ("penguin", "🐧"), ("bird", "🐦"), ("duck", "🦆"),
        ("owl", "🦉"), ("unicorn", "🦄"), ("bee", "🐝"), ("butterfly", "🦋"), ("snake", "🐍"),
        ("dino", "🦖"), ("octopus", "🐙"), ("shark", "🦈"), ("whale", "🐳"), ("dolphin", "🐬"),
        ("elephant", "🐘"), ("apple", "🍎"), ("banana", "🍌"), ("watermelon", "🍉"),
        ("grape", "🍇"), ("strawberry", "🍓"), ("mango", "🥭"), ("pineapple", "🍍"),
        ("avocado", "🥑"), ("pizza", "🍕"), ("burger", "🍔"), ("fries", "🍟"), ("hotdog", "🌭"),
        ("taco", "🌮"), ("sushi", "🍣"), ("noodle", "🍜"), ("ramen", "🍜"), ("curry", "🍛"),
        ("cake", "🎂"), ("birthday", "🎂"), ("cookie", "🍪"), ("donut", "🍩"), ("candy", "🍬"),
        ("chocolate", "🍫"), ("popcorn", "🍿"), ("coffee", "☕"), ("tea", "🍵"), ("boba", "🧋"),
        ("beer", "🍺"), ("cheers", "🥂"), ("wine", "🍷"), ("cocktail", "🍸"), ("ball", "⚽"),
        ("soccer", "⚽"), ("football", "🏈"), ("basketball", "🏀"), ("cricket", "🏏"),
        ("tennis", "🎾"), ("trophy", "🏆"), ("gold", "🥇"), ("medal", "🏅"), ("game", "🎮"),
        ("dart", "🎯"), ("music", "🎤"), ("guitar", "🎸"), ("drum", "🥁"), ("art", "🎨"),
        ("movie", "🎬"), ("car", "🚗"), ("taxi", "🚕"), ("bus", "🚌"), ("train", "🚄"),
        ("plane", "✈️"), ("rocket", "🚀"), ("ufo", "🛸"), ("ship", "🚢"), ("anchor", "⚓"),
        ("map", "🗺️"), ("beach", "🏖️"), ("island", "🏝️"), ("mountain", "⛰️"), ("camp", "🏕️"),
        ("home", "🏠"), ("house", "🏡"), ("castle", "🏰"), ("phone", "📱"), ("laptop", "💻"),
        ("keyboard", "⌨️"), ("camera", "📷"), ("tv", "📺"), ("battery", "🔋"), ("bulb", "💡"),
        ("idea", "💡"), ("money", "💰"), ("cash", "💵"), ("card", "💳"), ("gem", "💎"),
        ("tool", "🛠️"), ("hammer", "🔨"), ("gear", "⚙️"), ("bomb", "💣"), ("knife", "🔪"),
        ("crystal", "🔮"), ("heart", "❤️"), ("orange heart", "🧡"), ("yellow heart", "💛"),
        ("green heart", "💚"), ("blue heart", "💙"), ("purple heart", "💜"),
        ("black heart", "🖤"), ("white heart", "🤍"), ("broken", "💔"), ("sparkling heart", "💖"),
        ("check", "✅"), ("cross", "❌"), ("warning", "⚠️"), ("recycle", "♻️"), ("globe", "🌐"),
        ("star", "⭐"), ("rain", "🌧️"), ("sun", "☀️"), ("moon", "🌙"), ("cloud", "☁️"),
        ("snow", "❄️"), ("rainbow", "🌈"), ("flower", "🌸"), ("rose", "🌹"), ("plant", "🪴"),
        ("tree", "🌳"), ("leaf", "🍃"), ("gift", "🎁"), ("balloon", "🎈"), ("confetti", "🎊"),
        ("celebrate", "🎉"), ("crown", "👑"), ("ring", "💍"), ("glasses", "🕶️"), ("bag", "👜"),
        ("flag", "🏳️"), ("rainbow flag", "🏳️‍🌈"), ("pirate", "🏴‍☠️"), ("finish", "🏁"),
        ("india", "🇮🇳"), ("usa", "🇺🇸"), ("america", "🇺🇸"), ("uk", "🇬🇧"), ("britain", "🇬🇧"),
        ("canada", "🇨🇦"), ("australia", "🇦🇺"), ("japan", "🇯🇵"), ("germany", "🇩🇪"),
        ("france", "🇫🇷"), ("uae", "🇦🇪"), ("singapore", "🇸🇬"), ("brazil", "🇧🇷"),
    ]

    static func search(_ query: String) -> [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out: [String] = []
        for (name, emoji) in names where name.contains(q) && !out.contains(emoji) {
            out.append(emoji)
            if out.count >= 24 { break }
        }
        return out
    }
}
