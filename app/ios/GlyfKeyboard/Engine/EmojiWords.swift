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
