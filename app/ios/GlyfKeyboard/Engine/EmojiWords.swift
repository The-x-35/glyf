import Foundation

/// The emoji a word brings to mind, for the strip's third slot while it is
/// typed and after it ("happy birthday" → 🎂, "pizza" → 🍕, "lol" → 😂), as
/// Gboard and Apple's bar offer one (Arpit, 2026-10-07: suggestions should
/// feel "crazy helpful"). Chat words only, one emoji each; nothing the
/// person wouldn't have reached for. EmojiWords.kt is Android's twin.
enum EmojiWords {
    static func emoji(for word: String) -> String? {
        var key = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if key.isEmpty { return nil }
        if let hit = table[key] { return hit }
        if key.hasSuffix("s"), key.count > 3 { key.removeLast(); return table[key] }
        return nil
    }

    private static let table: [String: String] = [
        // feelings
        "lol": "😂", "lmao": "😂", "haha": "😂", "hahaha": "😂", "rofl": "🤣", "funny": "😂", "hilarious": "🤣",
        "love": "❤️", "loved": "❤️", "heart": "❤️", "xoxo": "😘", "kiss": "😘", "kisses": "😘", "hug": "🤗", "hugs": "🤗",
        "happy": "😊", "smile": "😊", "glad": "😊", "excited": "🤩", "yay": "🥳", "woohoo": "🥳", "party": "🥳",
        "sad": "😢", "cry": "😭", "crying": "😭", "tears": "😭", "miss": "🥺", "please": "🙏", "pls": "🙏", "plz": "🙏",
        "thanks": "🙏", "thank": "🙏", "thx": "🙏", "ty": "🙏", "grateful": "🙏", "pray": "🙏", "praying": "🙏",
        "sorry": "🙏", "oops": "🙈", "awkward": "😬", "yikes": "😬", "omg": "😱", "shocked": "😱", "wow": "😮", "whoa": "😮",
        "angry": "😠", "mad": "😡", "furious": "😡", "annoyed": "😤", "ugh": "😩", "tired": "😴", "sleepy": "😴", "sleep": "😴",
        "exhausted": "😩", "bored": "😑", "meh": "😐", "hmm": "🤔", "thinking": "🤔", "think": "🤔", "idk": "🤷", "shrug": "🤷",
        "cool": "😎", "nice": "👍", "great": "👍", "awesome": "🙌", "amazing": "🤩", "perfect": "👌", "ok": "👌", "okay": "👌",
        "yes": "✅", "done": "✅", "agreed": "✅", "deal": "🤝", "no": "❌", "nope": "❌", "wrong": "❌", "stop": "🛑",
        "wait": "⏳", "soon": "🔜", "late": "⏰", "hurry": "🏃", "running": "🏃", "run": "🏃", "omw": "🏃",
        "sick": "🤒", "fever": "🤒", "ill": "🤒", "hospital": "🏥", "doctor": "🩺", "medicine": "💊",
        "fire": "🔥", "lit": "🔥", "hot": "🥵", "cold": "🥶", "freezing": "🥶", "sweating": "😓", "nervous": "😬", "scared": "😨",
        "dead": "💀", "kidding": "😜", "joking": "😜", "wink": "😉", "silly": "🤪", "crazy": "🤪", "clown": "🤡", "nerd": "🤓",
        "strong": "💪", "gym": "💪", "workout": "💪", "muscle": "💪", "flex": "💪", "clap": "👏", "bravo": "👏", "applause": "👏",
        "eyes": "👀", "look": "👀", "watching": "👀", "mindblown": "🤯", "boom": "💥", "bang": "💥",
        "congrats": "🎉", "congratulations": "🎉", "celebrate": "🎉", "cheers": "🥂", "toast": "🥂", "champagne": "🍾",
        "birthday": "🎂", "bday": "🎂", "cake": "🎂", "gift": "🎁", "present": "🎁", "balloon": "🎈", "balloons": "🎈",
        "wedding": "💍", "ring": "💍", "engaged": "💍", "married": "💒", "anniversary": "💐", "flowers": "💐", "rose": "🌹",
        "christmas": "🎄", "xmas": "🎄", "santa": "🎅", "diwali": "🪔", "halloween": "🎃", "pumpkin": "🎃", "easter": "🐣",
        "newyear": "🎆", "fireworks": "🎆", "holiday": "🏖️", "vacation": "🏖️", "beach": "🏖️", "trip": "✈️", "travel": "✈️",
        // food and drink
        "pizza": "🍕", "burger": "🍔", "fries": "🍟", "taco": "🌮", "tacos": "🌮", "burrito": "🌯", "sushi": "🍣", "ramen": "🍜",
        "noodles": "🍜", "pasta": "🍝", "spaghetti": "🍝", "salad": "🥗", "sandwich": "🥪", "bread": "🍞", "cheese": "🧀", "egg": "🥚",
        "eggs": "🥚", "bacon": "🥓", "steak": "🥩", "chicken": "🍗", "rice": "🍚", "curry": "🍛", "biryani": "🍛", "soup": "🍲",
        "breakfast": "🍳", "lunch": "🍱", "dinner": "🍽️", "brunch": "🥞", "pancakes": "🥞", "waffle": "🧇", "dessert": "🍰",
        "icecream": "🍦", "cookie": "🍪", "cookies": "🍪", "donut": "🍩", "chocolate": "🍫", "candy": "🍬", "popcorn": "🍿",
        "apple": "🍎", "banana": "🍌", "mango": "🥭", "strawberry": "🍓", "watermelon": "🍉", "avocado": "🥑", "lemon": "🍋",
        "coffee": "☕", "latte": "☕", "espresso": "☕", "tea": "🍵", "chai": "🍵", "matcha": "🍵", "boba": "🧋", "juice": "🧃",
        "water": "💧", "beer": "🍺", "beers": "🍻", "wine": "🍷", "cocktail": "🍹", "cocktails": "🍹", "drinks": "🍻", "drink": "🍹",
        "whiskey": "🥃", "shots": "🥃", "milk": "🥛", "hungry": "😋", "yum": "😋", "yummy": "😋", "delicious": "😋", "starving": "😋",
        // things and places
        "home": "🏠", "house": "🏠", "office": "🏢", "work": "💼", "school": "🏫", "college": "🎓", "graduation": "🎓", "exam": "📝",
        "car": "🚗", "taxi": "🚕", "uber": "🚕", "bus": "🚌", "train": "🚆", "metro": "🚇", "bike": "🚲", "flight": "✈️", "plane": "✈️",
        "airport": "✈️", "ship": "🚢", "rocket": "🚀", "launch": "🚀", "moon": "🌙", "night": "🌙", "goodnight": "🌙", "sun": "☀️",
        "sunny": "☀️", "morning": "☀️", "rain": "🌧️", "raining": "🌧️", "storm": "⛈️", "snow": "❄️", "rainbow": "🌈", "star": "⭐",
        "stars": "✨", "sparkle": "✨", "magic": "✨", "phone": "📱", "call": "📞", "calling": "📞", "mail": "📧", "email": "📧",
        "message": "💬", "text": "💬", "chat": "💬", "camera": "📷", "photo": "📸", "photos": "📸", "selfie": "🤳", "video": "🎥",
        "movie": "🎬", "movies": "🎬", "netflix": "📺", "tv": "📺", "music": "🎵", "song": "🎵", "sing": "🎤", "singing": "🎤",
        "dance": "💃", "dancing": "💃", "guitar": "🎸", "concert": "🎤", "game": "🎮", "games": "🎮", "gaming": "🎮", "football": "⚽",
        "soccer": "⚽", "cricket": "🏏", "basketball": "🏀", "tennis": "🎾", "golf": "⛳", "goal": "⚽", "win": "🏆", "won": "🏆",
        "winner": "🏆", "trophy": "🏆", "medal": "🏅", "champion": "🏆", "book": "📚", "books": "📚", "reading": "📖", "study": "📚",
        "studying": "📚", "money": "💰", "cash": "💵", "rich": "🤑", "broke": "💸", "paid": "💸", "pay": "💸", "bank": "🏦",
        "shopping": "🛍️", "sale": "🛍️", "cart": "🛒", "key": "🔑", "keys": "🔑", "lock": "🔒", "idea": "💡", "light": "💡",
        "clock": "⏰", "alarm": "⏰", "time": "⏰", "calendar": "📅", "date": "📅", "meeting": "📅", "deadline": "⏳",
        "dog": "🐶", "puppy": "🐶", "cat": "🐱", "kitten": "🐱", "bird": "🐦", "fish": "🐟", "horse": "🐴", "cow": "🐮", "pig": "🐷",
        "monkey": "🐵", "bear": "🐻", "panda": "🐼", "lion": "🦁", "tiger": "🐯", "snake": "🐍", "butterfly": "🦋", "bee": "🐝",
        "baby": "👶", "kid": "🧒", "kids": "🧒", "family": "👨‍👩‍👧", "mom": "👩", "dad": "👨", "bro": "👊", "bruh": "😑",
        "bye": "👋", "goodbye": "👋", "hi": "👋", "hello": "👋", "hey": "👋", "welcome": "🙌", "hands": "🙌", "fist": "👊", "punch": "👊",
        "luck": "🍀", "lucky": "🍀", "goodluck": "🍀", "100": "💯", "hundred": "💯", "warning": "⚠️", "careful": "⚠️", "danger": "⚠️",
        "poop": "💩", "ghost": "👻", "alien": "👽", "robot": "🤖", "unicorn": "🦄", "crown": "👑", "queen": "👑", "king": "👑",
        "diamond": "💎", "bomb": "💣", "knife": "🔪", "sword": "⚔️", "shield": "🛡️", "flag": "🏁", "finish": "🏁", "goodjob": "👏",
    ]
}

/// The emoji a person puts after their own words, as they type them ("love
/// you ❤️❤️❤️", "haha 😂"): found in the text before the caret, so the
/// engine can learn the habit (PersonalLexicon.noteEmoji) and offer the same
/// run in the emoji slot next time (Arpit, 2026-11-06: "a person who uses
/// emojis a lot ... we can learn that as well"). Pure logic, unit-tested.
enum EmojiRuns {

    /// Longer runs are decoration, not a habit worth a slot.
    static let longest = 6

    struct Run: Equatable {
        /// The emoji exactly as typed, one to `longest` of them.
        var emoji: String
        /// The word just before them ("you"), and the one before that ("love").
        var word: String
        var previous: String?
        /// The text up to the run's end: one occurrence is learned once.
        var anchor: String
    }

    /// A picture emoji, not a digit or a # that also has an emoji form.
    static func isEmoji(_ c: Character) -> Bool {
        guard let first = c.unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        // ❤️ is U+2764 + VS16; 1️⃣ is a keycap; 👨‍👩‍👧 joins with ZWJ.
        return first.properties.isEmoji && c.unicodeScalars.count > 1
            && c.unicodeScalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 || $0.value == 0x200D }
    }

    /// The emoji run the text ends with (spaces after it don't count) and
    /// the words before it. Nil without a word right before the run: after
    /// a sentence's end, a link or a number there is nothing to learn it by.
    static func trailing(_ text: String) -> Run? {
        var body = Substring(text)
        while let c = body.last, c.isWhitespace { body = body.dropLast() }
        let anchor = String(body)
        var count = 0
        while let c = body.last, isEmoji(c) {
            body = body.dropLast()
            count += 1
        }
        guard count > 0, count <= longest else { return nil }
        let emoji = String(anchor.suffix(count))
        while let c = body.last, WordTracker.spaces.contains(c) { body = body.dropLast() }
        let rest = String(body)
        let word = WordTracker.currentWord(beforeContext: rest)
        guard word.count >= 2, word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }),
              !WordTracker.insideLinkOrAddress(beforeContext: rest) else { return nil }
        // A word of its own, not the tail of "tryglyf.com" or "v2.beta".
        if let c = rest.dropLast(word.count).last, !c.isWhitespace, !"(\"“‘".contains(c) { return nil }
        let previous = WordTracker.previousWord(beforeContext: rest)
            .flatMap { p in p.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) ? p : nil }
        return Run(emoji: emoji, word: word, previous: previous, anchor: anchor)
    }

    /// A run the person has just finished, between two looks at the text
    /// before the caret: a space or a line break typed after it (or the
    /// run put in with its space, as a strip tap does), or the message sent
    /// (the field emptied). A draft the keyboard opens on teaches nothing:
    /// only a few characters may have come in since the last look.
    static func finished(seen: String, now: String) -> Run? {
        if let last = now.last, last.isWhitespace, let run = trailing(now) {
            let added = now.count - seen.count
            guard added >= 1, added <= run.emoji.count + 2 else { return nil }
            return run
        }
        if now.isEmpty, let last = seen.last, !last.isWhitespace { return trailing(seen) }
        return nil
    }
}
