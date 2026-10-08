package com.arpit.glyf.ime

/** The emoji a word brings to mind, for the strip's third slot while it is
 *  typed and after it ("happy birthday" → 🎂, "pizza" → 🍕, "lol" → 😂).
 *  Chat words only, one emoji each. Twin of iOS EmojiWords.swift. */
object EmojiWords {
    fun emoji(word: String): String? {
        var key = word.lowercase().trim { !it.isLetterOrDigit() }
        if (key.isEmpty()) return null
        table[key]?.let { return it }
        if (key.endsWith("s") && key.length > 3) { key = key.dropLast(1); return table[key] }
        return null
    }

    private val table: Map<String, String> = hashMapOf(
        "lol" to "😂", "lmao" to "😂", "haha" to "😂", "hahaha" to "😂", "rofl" to "🤣", "funny" to "😂", "hilarious" to "🤣", "love" to "❤️",
        "loved" to "❤️", "heart" to "❤️", "xoxo" to "😘", "kiss" to "😘", "kisses" to "😘", "hug" to "🤗", "hugs" to "🤗", "happy" to "😊",
        "smile" to "😊", "glad" to "😊", "excited" to "🤩", "yay" to "🥳", "woohoo" to "🥳", "party" to "🥳", "sad" to "😢", "cry" to "😭",
        "crying" to "😭", "tears" to "😭", "miss" to "🥺", "please" to "🙏", "pls" to "🙏", "plz" to "🙏", "thanks" to "🙏", "thank" to "🙏",
        "thx" to "🙏", "ty" to "🙏", "grateful" to "🙏", "pray" to "🙏", "praying" to "🙏", "sorry" to "🙏", "oops" to "🙈", "awkward" to "😬",
        "yikes" to "😬", "omg" to "😱", "shocked" to "😱", "wow" to "😮", "whoa" to "😮", "angry" to "😠", "mad" to "😡", "furious" to "😡",
        "annoyed" to "😤", "ugh" to "😩", "tired" to "😴", "sleepy" to "😴", "sleep" to "😴", "exhausted" to "😩", "bored" to "😑", "meh" to "😐",
        "hmm" to "🤔", "thinking" to "🤔", "think" to "🤔", "idk" to "🤷", "shrug" to "🤷", "cool" to "😎", "nice" to "👍", "great" to "👍",
        "awesome" to "🙌", "amazing" to "🤩", "perfect" to "👌", "ok" to "👌", "okay" to "👌", "yes" to "✅", "done" to "✅", "agreed" to "✅",
        "deal" to "🤝", "no" to "❌", "nope" to "❌", "wrong" to "❌", "stop" to "🛑", "wait" to "⏳", "soon" to "🔜", "late" to "⏰",
        "hurry" to "🏃", "running" to "🏃", "run" to "🏃", "omw" to "🏃", "sick" to "🤒", "fever" to "🤒", "ill" to "🤒", "hospital" to "🏥",
        "doctor" to "🩺", "medicine" to "💊", "fire" to "🔥", "lit" to "🔥", "hot" to "🥵", "cold" to "🥶", "freezing" to "🥶", "sweating" to "😓",
        "nervous" to "😬", "scared" to "😨", "dead" to "💀", "kidding" to "😜", "joking" to "😜", "wink" to "😉", "silly" to "🤪", "crazy" to "🤪",
        "clown" to "🤡", "nerd" to "🤓", "strong" to "💪", "gym" to "💪", "workout" to "💪", "muscle" to "💪", "flex" to "💪", "clap" to "👏",
        "bravo" to "👏", "applause" to "👏", "eyes" to "👀", "look" to "👀", "watching" to "👀", "mindblown" to "🤯", "boom" to "💥", "bang" to "💥",
        "congrats" to "🎉", "congratulations" to "🎉", "celebrate" to "🎉", "cheers" to "🥂", "toast" to "🥂", "champagne" to "🍾", "birthday" to "🎂", "bday" to "🎂",
        "cake" to "🎂", "gift" to "🎁", "present" to "🎁", "balloon" to "🎈", "balloons" to "🎈", "wedding" to "💍", "ring" to "💍", "engaged" to "💍",
        "married" to "💒", "anniversary" to "💐", "flowers" to "💐", "rose" to "🌹", "christmas" to "🎄", "xmas" to "🎄", "santa" to "🎅", "diwali" to "🪔",
        "halloween" to "🎃", "pumpkin" to "🎃", "easter" to "🐣", "newyear" to "🎆", "fireworks" to "🎆", "holiday" to "🏖️", "vacation" to "🏖️", "beach" to "🏖️",
        "trip" to "✈️", "travel" to "✈️", "pizza" to "🍕", "burger" to "🍔", "fries" to "🍟", "taco" to "🌮", "tacos" to "🌮", "burrito" to "🌯",
        "sushi" to "🍣", "ramen" to "🍜", "noodles" to "🍜", "pasta" to "🍝", "spaghetti" to "🍝", "salad" to "🥗", "sandwich" to "🥪", "bread" to "🍞",
        "cheese" to "🧀", "egg" to "🥚", "eggs" to "🥚", "bacon" to "🥓", "steak" to "🥩", "chicken" to "🍗", "rice" to "🍚", "curry" to "🍛",
        "biryani" to "🍛", "soup" to "🍲", "breakfast" to "🍳", "lunch" to "🍱", "dinner" to "🍽️", "brunch" to "🥞", "pancakes" to "🥞", "waffle" to "🧇",
        "dessert" to "🍰", "icecream" to "🍦", "cookie" to "🍪", "cookies" to "🍪", "donut" to "🍩", "chocolate" to "🍫", "candy" to "🍬", "popcorn" to "🍿",
        "apple" to "🍎", "banana" to "🍌", "mango" to "🥭", "strawberry" to "🍓", "watermelon" to "🍉", "avocado" to "🥑", "lemon" to "🍋", "coffee" to "☕",
        "latte" to "☕", "espresso" to "☕", "tea" to "🍵", "chai" to "🍵", "matcha" to "🍵", "boba" to "🧋", "juice" to "🧃", "water" to "💧",
        "beer" to "🍺", "beers" to "🍻", "wine" to "🍷", "cocktail" to "🍹", "cocktails" to "🍹", "drinks" to "🍻", "drink" to "🍹", "whiskey" to "🥃",
        "shots" to "🥃", "milk" to "🥛", "hungry" to "😋", "yum" to "😋", "yummy" to "😋", "delicious" to "😋", "starving" to "😋", "home" to "🏠",
        "house" to "🏠", "office" to "🏢", "work" to "💼", "school" to "🏫", "college" to "🎓", "graduation" to "🎓", "exam" to "📝", "car" to "🚗",
        "taxi" to "🚕", "uber" to "🚕", "bus" to "🚌", "train" to "🚆", "metro" to "🚇", "bike" to "🚲", "flight" to "✈️", "plane" to "✈️",
        "airport" to "✈️", "ship" to "🚢", "rocket" to "🚀", "launch" to "🚀", "moon" to "🌙", "night" to "🌙", "goodnight" to "🌙", "sun" to "☀️",
        "sunny" to "☀️", "morning" to "☀️", "rain" to "🌧️", "raining" to "🌧️", "storm" to "⛈️", "snow" to "❄️", "rainbow" to "🌈", "star" to "⭐",
        "stars" to "✨", "sparkle" to "✨", "magic" to "✨", "phone" to "📱", "call" to "📞", "calling" to "📞", "mail" to "📧", "email" to "📧",
        "message" to "💬", "text" to "💬", "chat" to "💬", "camera" to "📷", "photo" to "📸", "photos" to "📸", "selfie" to "🤳", "video" to "🎥",
        "movie" to "🎬", "movies" to "🎬", "netflix" to "📺", "tv" to "📺", "music" to "🎵", "song" to "🎵", "sing" to "🎤", "singing" to "🎤",
        "dance" to "💃", "dancing" to "💃", "guitar" to "🎸", "concert" to "🎤", "game" to "🎮", "games" to "🎮", "gaming" to "🎮", "football" to "⚽",
        "soccer" to "⚽", "cricket" to "🏏", "basketball" to "🏀", "tennis" to "🎾", "golf" to "⛳", "goal" to "⚽", "win" to "🏆", "won" to "🏆",
        "winner" to "🏆", "trophy" to "🏆", "medal" to "🏅", "champion" to "🏆", "book" to "📚", "books" to "📚", "reading" to "📖", "study" to "📚",
        "studying" to "📚", "money" to "💰", "cash" to "💵", "rich" to "🤑", "broke" to "💸", "paid" to "💸", "pay" to "💸", "bank" to "🏦",
        "shopping" to "🛍️", "sale" to "🛍️", "cart" to "🛒", "key" to "🔑", "keys" to "🔑", "lock" to "🔒", "idea" to "💡", "light" to "💡",
        "clock" to "⏰", "alarm" to "⏰", "time" to "⏰", "calendar" to "📅", "date" to "📅", "meeting" to "📅", "deadline" to "⏳", "dog" to "🐶",
        "puppy" to "🐶", "cat" to "🐱", "kitten" to "🐱", "bird" to "🐦", "fish" to "🐟", "horse" to "🐴", "cow" to "🐮", "pig" to "🐷",
        "monkey" to "🐵", "bear" to "🐻", "panda" to "🐼", "lion" to "🦁", "tiger" to "🐯", "snake" to "🐍", "butterfly" to "🦋", "bee" to "🐝",
        "baby" to "👶", "kid" to "🧒", "kids" to "🧒", "family" to "👨‍👩‍👧", "mom" to "👩", "dad" to "👨", "bro" to "👊", "bruh" to "😑",
        "bye" to "👋", "goodbye" to "👋", "hi" to "👋", "hello" to "👋", "hey" to "👋", "welcome" to "🙌", "hands" to "🙌", "fist" to "👊",
        "punch" to "👊", "luck" to "🍀", "lucky" to "🍀", "goodluck" to "🍀", "100" to "💯", "hundred" to "💯", "warning" to "⚠️", "careful" to "⚠️",
        "danger" to "⚠️", "poop" to "💩", "ghost" to "👻", "alien" to "👽", "robot" to "🤖", "unicorn" to "🦄", "crown" to "👑", "queen" to "👑",
        "king" to "👑", "diamond" to "💎", "bomb" to "💣", "knife" to "🔪", "sword" to "⚔️", "shield" to "🛡️", "flag" to "🏁", "finish" to "🏁",
        "goodjob" to "👏",
    )
}
