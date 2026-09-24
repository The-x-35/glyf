package com.demo.glyf.ime

/**
 * The emoji board's data, generated from the iOS keyboard's EmojiData.swift
 * and EmoticonData.swift (2026-09-24) so both keyboards carry the same lists,
 * in Apple's nine tabs. Regenerate rather than edit by hand.
 */
object EmojiData {

    /** id, the tab glyph's name (drawn by ToolIcon-style canvas code), the emoji. */
    val categories: List<Pair<String, List<String>>> by lazy {
        listOf(
            "smileys" to listOf(
                "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥲", "☺️", "😊", "😇",
                "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛",
                "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥸", "🤩", "🥳", "😏", "😒",
                "😞", "😔", "😟", "😕", "🙁", "☹️", "😣", "😖", "😫", "😩", "🥺", "😢",
                "😭", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰",
                "😥", "😓", "🤗", "🤔", "🫡", "🤭", "🫢", "🤫", "😶", "🫥", "😐", "😑",
                "😬", "🙄", "😯", "😴", "🤤", "😪", "😮‍💨", "🤢", "🤮", "🤧", "😷", "🤒",
                "🤕", "🤑", "🤠", "😈", "👿", "🤡", "💀", "☠️", "👻", "👽", "🤖", "💩",
                "🔥", "✨", "💫", "💯", "💢", "💥", "💦", "💤", "👋", "🤚", "🖐️", "✋",
                "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🫰", "🤟", "🤘", "🤙", "👈", "👉",
                "👆", "👇", "☝️", "👍", "👎", "✊", "👊", "🤛", "🤜", "👏", "🙌", "🫶",
                "👐", "🤲", "🤝", "🙏", "✍️", "💅", "🤳", "💪", "🦾", "🧠", "👀", "👁️",
                "👄", "🫦", "👶", "🧒", "👦", "👧", "🧑", "👨", "👩", "🧔", "👱", "🧓",
                "👴", "👵", "🙍", "🙎", "🙅", "🙆", "💁", "🙋", "🧏", "🙇", "🤦", "🤷",
                "👮", "🕵️", "💂", "👷", "🫅", "🤴", "👸", "👳", "👲", "🧕", "🤵", "👰",
                "🤰", "🤱", "👼", "🎅", "🤶", "🦸", "🦹", "🧙", "🧚", "🧛", "🧜", "🧝",
                "🧞", "🧟",
            ),
            "animals" to listOf(
                "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨", "🐯", "🦁",
                "🐮", "🐷", "🐸", "🐵", "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤",
                "🐣", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🪱", "🐛",
                "🦋", "🐌", "🐞", "🐜", "🦟", "🦗", "🕷️", "🦂", "🐢", "🐍", "🦎", "🦖",
                "🦕", "🐙", "🦑", "🦐", "🦞", "🦀", "🐡", "🐠", "🐟", "🐬", "🐳", "🐋",
                "🦈", "🐊", "🐅", "🐆", "🦓", "🦍", "🦧", "🐘", "🦛", "🦏", "🐪", "🐫",
                "🦒", "🦘", "🐃",
            ),
            "food" to listOf(
                "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒",
                "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑", "🥦", "🥬", "🥒", "🌶️",
                "🫑", "🌽", "🥕", "🫒", "🧄", "🧅", "🥔", "🍠", "🥐", "🥯", "🍞", "🥖",
                "🥨", "🧀", "🥚", "🍳", "🧈", "🥞", "🧇", "🥓", "🥩", "🍗", "🍖", "🌭",
                "🍔", "🍟", "🍕", "🫓", "🥪", "🥙", "🧆", "🌮", "🌯", "🫔", "🥗", "🥘",
                "🍝", "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🦪", "🍤", "🍙", "🍚", "🍘",
                "🍥", "🥠", "🍢", "🍡", "🍧", "🍨", "🍦", "🥧", "🧁", "🍰", "🎂", "🍮",
                "🍭", "🍬", "🍫", "🍿", "🍩", "🍪", "☕", "🍵", "🧋", "🥤", "🧃", "🍺",
                "🍻", "🥂", "🍷", "🥃", "🍸", "🍹", "🍾",
            ),
            "activity" to listOf(
                "⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🪀", "🏓",
                "🏸", "🏒", "🏑", "🥍", "🏏", "🪃", "🥅", "⛳", "🪁", "🏹", "🎣", "🤿",
                "🥊", "🥋", "🎽", "🛹", "🛼", "🛷", "⛸️", "🥌", "🎿", "⛷️", "🏂", "🏋️",
                "🤼", "🤸", "⛹️", "🤺", "🤾", "🏌️", "🏇", "🧘", "🏄", "🏊", "🤽", "🚣",
                "🧗", "🚵", "🚴", "🏆", "🥇", "🥈", "🥉", "🏅", "🎖️", "🎗️", "🎫", "🎟️",
                "🎪", "🤹", "🎭", "🩰", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🪘",
                "🎷", "🎺", "🪗", "🎸", "🪕", "🎻", "🎲", "♟️", "🎯", "🎳", "🎮", "🎰",
                "🧩",
            ),
            "travel" to listOf(
                "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐", "🛻", "🚚",
                "🚛", "🚜", "🦯", "🦽", "🦼", "🛴", "🚲", "🛵", "🏍️", "🛺", "🚨", "🚔",
                "🚍", "🚘", "🚖", "🚡", "🚠", "🚟", "🚃", "🚋", "🚞", "🚝", "🚄", "🚅",
                "🚈", "🚂", "🚆", "🚇", "🚊", "🚉", "✈️", "🛫", "🛬", "🛩️", "💺", "🛰️",
                "🚀", "🛸", "🚁", "🛶", "⛵", "🚤", "🛥️", "🛳️", "⛴️", "🚢", "⚓", "🪝",
                "⛽", "🚧", "🚦", "🚥", "🗺️", "🗿", "🗽", "🗼", "🏰", "🏯", "🏟️", "🎡",
                "🎢", "🎠", "⛲", "⛱️", "🏖️", "🏝️", "🏜️", "🌋", "⛰️", "🏔️", "🗻", "🏕️",
                "⛺", "🛖", "🏠", "🏡", "🏘️", "🏚️",
            ),
            "objects" to listOf(
                "⌚", "📱", "📲", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "🖲️", "🕹️", "🗜️", "💽",
                "💾", "💿", "📀", "📼", "📷", "📸", "📹", "🎥", "📽️", "🎞️", "📞", "☎️",
                "📟", "📠", "📺", "📻", "🎙️", "🎚️", "🎛️", "🧭", "⏱️", "⏲️", "⏰", "🕰️",
                "⌛", "⏳", "📡", "🔋", "🪫", "🔌", "💡", "🔦", "🕯️", "🪔", "🧯", "🛢️",
                "💸", "💵", "💴", "💶", "💷", "🪙", "💰", "💳", "💎", "⚖️", "🪜", "🧰",
                "🪛", "🔧", "🔨", "⚒️", "🛠️", "⛏️", "🪚", "🔩", "⚙️", "🪤", "🧱", "⛓️",
                "🧲", "🔫", "💣", "🧨", "🪓", "🔪", "🗡️", "⚔️", "🛡️", "🚬", "⚰️", "🪦",
                "⚱️", "🏺", "🔮", "📿", "🧿", "💈",
            ),
            "symbols" to listOf(
                "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❤️‍🔥", "❤️‍🩹",
                "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️", "✝️", "☪️",
                "🕉️", "☸️", "✡️", "🔯", "🕎", "☯️", "☦️", "🛐", "⛎", "♈", "♉", "♊",
                "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓", "🆔", "⚛️", "✅",
                "☑️", "✔️", "❌", "❎", "➕", "➖", "➗", "✖️", "🟰", "💲", "💱", "™️",
                "©️", "®️", "〰️", "➰", "➿", "🔚", "🔙", "🔛", "🔝", "🔜", "⚠️", "🚸",
                "🔱", "⚜️", "🔰", "♻️", "🈯", "💹", "❇️", "✳️", "❎", "🌐", "💠", "Ⓜ️",
                "🌀", "💤", "🏧", "🚾", "♿", "🅿️",
            ),
            "flags" to flags,
        )
    }

    val titles = mapOf(
        "recents" to "FREQUENTLY USED",
        "smileys" to "SMILEYS & PEOPLE",
        "animals" to "ANIMALS & NATURE",
        "food" to "FOOD & DRINK",
        "activity" to "ACTIVITY",
        "travel" to "TRAVEL & PLACES",
        "objects" to "OBJECTS",
        "symbols" to "SYMBOLS",
        "flags" to "FLAGS",
    )

    /** Country flags from ISO codes, after the flags that are not countries. */
    val flags: List<String> by lazy {
        val codes = "AF AL DZ AR AM AU AT AZ BH BD BE BT BO BA BR BG KH CA CL CN CO CR HR CU CY CZ DK DO EC EG SV EE ET FI FR GE DE GH GR GT HN HK HU IS IN ID IR IQ IE IL IT JM JP JO KZ KE KW LA LV LB LT LU MY MV MT MX MN MA MM NP NL NZ NG NO OM PK PA PY PE PH PL PT QA RO RU SA RS SG SK SI ZA KR ES LK SE CH TW TZ TH TR UG UA AE GB US UY UZ VE VN YE ZM ZW"
        listOf("🏁", "🚩", "🎌", "🏴", "🏳️", "🏳️‍🌈", "🏳️‍⚧️", "🏴‍☠️", "🇺🇳") +
            codes.split(" ").map { code ->
                code.map { c -> String(Character.toChars(0x1F1E6 + (c - 'A'))) }.joinToString("")
            }
    }

    val skinToneBases: Set<String> = setOf(
        "👋", "🤚", "🖐️", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🫰", "🤟",
        "🤘", "🤙", "👈", "👉", "👆", "👇", "☝️", "👍", "👎", "✊", "👊", "🤛",
        "🤜", "👏", "🙌", "🫶", "👐", "🤲", "🙏", "✍️", "💅", "🤳", "💪", "👶",
        "🧒", "👦", "👧", "🧑", "👨", "👩", "🧓", "👴", "👵", "🙋", "🙇", "🤦",
        "🤷", "🎅", "🤶", "💁", "🙅", "🙆",
    )
    val skinTones = listOf("🏻", "🏼", "🏽", "🏾", "🏿")

    fun variants(base: String): List<String> {
        if (base !in skinToneBases) return listOf(base)
        val stripped = base.replace("\uFE0F", "")
        return listOf(base) + skinTones.map { stripped + it }
    }

    /** Small common-name index for search. name to emoji. */
    val names: List<Pair<String, String>> = listOf(
        "laugh" to "😂", "joy" to "😂", "rofl" to "🤣", "smile" to "😄", "happy" to "😊",
        "grin" to "😁", "wink" to "😉", "love" to "😍", "heart eyes" to "😍", "kiss" to "😘",
        "cool" to "😎", "party" to "🥳", "smirk" to "😏", "sad" to "😢", "cry" to "😭",
        "angry" to "😡", "rage" to "🤬", "mind blown" to "🤯", "shock" to "😱", "think" to "🤔",
        "hug" to "🤗", "shush" to "🤫", "sleep" to "😴", "sick" to "🤒", "mask" to "😷",
        "devil" to "😈", "clown" to "🤡", "skull" to "💀", "ghost" to "👻", "alien" to "👽",
        "robot" to "🤖", "poop" to "💩", "fire" to "🔥", "sparkle" to "✨", "hundred" to "💯",
        "wave" to "👋", "ok" to "👌", "peace" to "✌️", "crossed" to "🤞", "rock" to "🤘",
        "call" to "🤙", "point" to "👉", "up" to "👍", "thumbs up" to "👍", "down" to "👎",
        "thumbs down" to "👎", "fist" to "✊", "punch" to "👊", "clap" to "👏", "raise" to "🙌",
        "pray" to "🙏", "thanks" to "🙏", "muscle" to "💪", "flex" to "💪", "eyes" to "👀",
        "brain" to "🧠", "shrug" to "🤷", "facepalm" to "🤦", "dog" to "🐶", "cat" to "🐱",
        "fox" to "🦊", "bear" to "🐻", "panda" to "🐼", "lion" to "🦁", "pig" to "🐷",
        "monkey" to "🐵", "chicken" to "🐔", "penguin" to "🐧", "bird" to "🐦", "duck" to "🦆",
        "owl" to "🦉", "unicorn" to "🦄", "bee" to "🐝", "butterfly" to "🦋", "snake" to "🐍",
        "dino" to "🦖", "octopus" to "🐙", "shark" to "🦈", "whale" to "🐳", "dolphin" to "🐬",
        "elephant" to "🐘", "apple" to "🍎", "banana" to "🍌", "watermelon" to "🍉", "grape" to "🍇",
        "strawberry" to "🍓", "mango" to "🥭", "pineapple" to "🍍", "avocado" to "🥑", "pizza" to "🍕",
        "burger" to "🍔", "fries" to "🍟", "hotdog" to "🌭", "taco" to "🌮", "sushi" to "🍣",
        "noodle" to "🍜", "ramen" to "🍜", "curry" to "🍛", "cake" to "🎂", "birthday" to "🎂",
        "cookie" to "🍪", "donut" to "🍩", "candy" to "🍬", "chocolate" to "🍫", "popcorn" to "🍿",
        "coffee" to "☕", "tea" to "🍵", "boba" to "🧋", "beer" to "🍺", "cheers" to "🥂",
        "wine" to "🍷", "cocktail" to "🍸", "ball" to "⚽", "soccer" to "⚽", "football" to "🏈",
        "basketball" to "🏀", "cricket" to "🏏", "tennis" to "🎾", "trophy" to "🏆", "gold" to "🥇",
        "medal" to "🏅", "game" to "🎮", "dart" to "🎯", "music" to "🎤", "guitar" to "🎸",
        "drum" to "🥁", "art" to "🎨", "movie" to "🎬", "car" to "🚗", "taxi" to "🚕",
        "bus" to "🚌", "train" to "🚄", "plane" to "✈️", "rocket" to "🚀", "ufo" to "🛸",
        "ship" to "🚢", "anchor" to "⚓", "map" to "🗺️", "beach" to "🏖️", "island" to "🏝️",
        "mountain" to "⛰️", "camp" to "🏕️", "home" to "🏠", "house" to "🏡", "castle" to "🏰",
        "phone" to "📱", "laptop" to "💻", "keyboard" to "⌨️", "camera" to "📷", "tv" to "📺",
        "battery" to "🔋", "bulb" to "💡", "idea" to "💡", "money" to "💰", "cash" to "💵",
        "card" to "💳", "gem" to "💎", "tool" to "🛠️", "hammer" to "🔨", "gear" to "⚙️",
        "bomb" to "💣", "knife" to "🔪", "crystal" to "🔮", "heart" to "❤️", "orange heart" to "🧡",
        "yellow heart" to "💛", "green heart" to "💚", "blue heart" to "💙", "purple heart" to "💜", "black heart" to "🖤",
        "white heart" to "🤍", "broken" to "💔", "sparkling heart" to "💖", "check" to "✅", "cross" to "❌",
        "warning" to "⚠️", "recycle" to "♻️", "globe" to "🌐", "star" to "⭐", "rain" to "🌧️",
        "sun" to "☀️", "moon" to "🌙", "cloud" to "☁️", "snow" to "❄️", "rainbow" to "🌈",
        "flower" to "🌸", "rose" to "🌹", "plant" to "🪴", "tree" to "🌳", "leaf" to "🍃",
        "gift" to "🎁", "balloon" to "🎈", "confetti" to "🎊", "celebrate" to "🎉", "crown" to "👑",
        "ring" to "💍", "glasses" to "🕶️", "bag" to "👜", "flag" to "🏳️", "rainbow flag" to "🏳️‍🌈",
        "pirate" to "🏴‍☠️", "finish" to "🏁", "india" to "🇮🇳", "usa" to "🇺🇸", "america" to "🇺🇸",
        "uk" to "🇬🇧", "britain" to "🇬🇧", "canada" to "🇨🇦", "australia" to "🇦🇺", "japan" to "🇯🇵",
        "germany" to "🇩🇪", "france" to "🇫🇷", "uae" to "🇦🇪", "singapore" to "🇸🇬", "brazil" to "🇧🇷",
    )

    fun search(query: String): List<String> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        val out = mutableListOf<String>()
        for ((name, emoji) in names) {
            if (name.contains(q) && emoji !in out) out.add(emoji)
            if (out.size >= 24) break
        }
        return out
    }
}

/** Text emoticons for the board's :-) page: plain text, typed as it is. */
object EmoticonData {
    val categories: List<Triple<String, String, List<String>>> = listOf(
        Triple("classic", "Classic", listOf(
            ":-)", ":)", ";-)", ";)", ":-D", ":D", "XD", ":-P",
            ":P", ":-(", ":(", ":'(", ":-O", ":O", ":-*", ":*",
            ":-|", ":/", ":-/", ">:(", "B-)", "8-)", "<3", "</3",
            "^_^", "^^", "-_-", "o_O", "O_o", ">_<", "T_T", ":3",
            "=)", "=D", "xD", "(:", "D:", ":-]", ":-[", "o:-)",
            "}:-)",
        )),
        Triple("smiling", "Smiling", listOf(
            "(◕‿◕)", "(^‿^)", "(｡◕‿◕｡)", "(✿◠‿◠)", "(◠‿◠)", "(＾▽＾)", "(ᵔ◡ᵔ)", "(´▽`)",
            "٩(◕‿◕)۶", "(o^▽^o)", "(⌒‿⌒)", "(✧ω✧)", "ヽ(´▽`)/", "(*^▽^*)", "(^_^)", "(^o^)",
            "(≧▽≦)", "(⁀ᗢ⁀)", "(´∀`)", "(•‿•)", "ʘ‿ʘ", "(≧◡≦)", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "\\(^o^)/",
            "(^▽^)",
        )),
        Triple("love", "Love", listOf(
            "(♥ω♥)", "(´∀`)♡", "(｡♥‿♥｡)", "(˘³˘)♥", "(*♡∀♡)", "♥‿♥", "(◍•ᴗ•◍)❤", "(灬º‿º灬)♡",
            "(づ￣ ³￣)づ", "(っ˘з(˘⌣˘ )", "♡(ˊ͈ ॢ꒳ ॢˋ͈)", "(´ε｀ )♡", "(ღ˘⌣˘ღ)", "(♡°▽°♡)", "♡＾▽＾♡", "(*˘︶˘*).｡.:*♡",
            "( ˘ ³˘)♥", "(✿ ♥‿♥)", "♡", "❤(ɔˆз(ˆ⌣ˆc)",
        )),
        Triple("hugs", "Hugs", listOf(
            "(っ´▽`)っ", "(づ｡◕‿‿◕｡)づ", "⊂(・▽・⊂)", "(つ≧▽≦)つ", "(っ＾▽＾)っ", "⊂(´・ω・｀⊂)", "(⊃｡•́‿•̀｡)⊃", "(づ ◕‿◕ )づ",
            "(っ◕‿◕)っ", "ლ(╹◡╹ლ)", "(ɔˆ ³(ˆ⌣ˆc)", "(⊃・ᴗ・)⊃",
        )),
        Triple("sad", "Sad", listOf(
            "(╥﹏╥)", "(T_T)", "(ಥ﹏ಥ)", "(;﹏;)", "(´；ω；`)", "(ㅠ﹏ㅠ)", "(｡•́︿•̀｡)", "(´・_・`)",
            "(-_-;)", "(︶︹︺)", "(ノ_<。)", "(｡╯︵╰｡)", "(>_<)", "(ಥ_ಥ)", "(´°̥̥̥̥̥̥̥̥ω°̥̥̥̥̥̥̥̥｀)", "(-_-)",
            "(ᗒᗣᗕ)՞",
        )),
        Triple("angry", "Angry", listOf(
            "(╬ Ò﹏Ó)", "(ノಠ益ಠ)ノ彡┻━┻", "(╯°□°）╯︵ ┻━┻", "(ಠ_ಠ)", "(¬_¬)", "ヽ(`Д´)ﾉ", "(＃`Д´)", "(`皿´＃)",
            "ಠ╭╮ಠ", "(ง'̀-'́)ง", "(눈_눈)", "(╯‵□′)╯︵┻━┻", "┬─┬ノ( º _ ºノ)", "(ꐦ°᷄д°᷅)",
        )),
        Triple("surprised", "Surprised", listOf(
            "(⊙_⊙)", "(°ロ°)", "(O_O)", "(ﾟДﾟ;)", "Σ(°△°|||)", "(゜-゜)", "(⊙０⊙)", "(°o°)",
            "w(°ｏ°)w", "(o_O)", "Σ(ﾟДﾟ)", "(＠_＠;)", "(ʘᗩʘ')",
        )),
        Triple("cool", "Cool", listOf(
            "(⌐■_■)", "( •_•)>⌐■-■", "(☞ﾟヮﾟ)☞", "☜(ﾟヮﾟ☜)", "ᕦ(ò_óˇ)ᕤ", "(ง •̀_•́)ง", "(•̀ᴗ•́)و", "( ͡° ͜ʖ ͡°)",
            "(>‿◠)✌", "ᕕ( ᐛ )ᕗ", "(ಠ‿ಠ)", "(￣ー￣)b", "d(^_^)b", "(b ᵔ▽ᵔ)b",
        )),
        Triple("shrug", "Shrug", listOf(
            "¯\\_(ツ)_/¯", "¯\\(°_o)/¯", "┐(´ー｀)┌", "ヽ(ー_ー )ノ", "┐(︶▽︶)┌", "(・_・ヾ", "(￣ヘ￣)", "(•_•)",
            "(・・?", "ʅ(°_°)ʃ",
        )),
        Triple("animals", "Animals", listOf(
            "ʕ•ᴥ•ʔ", "(=^･ω･^=)", "(=^‥^=)", "ʕ·ᴥ·ʔ", "(ᵔᴥᵔ)", "U・ᴥ・U", "∪･ω･∪", "(・⊝・)",
            "><(((('>", "(`・ω・´)", "(=ↀωↀ=)", "₍ᐢ•ﻌ•ᐢ₎", "ʕっ•ᴥ•ʔっ", "(•ө•)♡", "~(˘▾˘~)", "くコ:彡",
        )),
    )

    fun items(id: String): List<String> = categories.firstOrNull { it.first == id }?.third ?: emptyList()
}
