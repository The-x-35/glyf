package com.arpit.glyf.ime

/** Everyday phrases in other languages, on the phone: "thank you in
 *  spanish" → gracias, in place, with no AI run spent (2026-10-14). The
 *  twin of Smart.swift's `phraseIn`; the table is the same, row for row. */
object Phrases {
    private val languages: List<Pair<List<String>, String>> = listOf(
        listOf("spanish", "español", "espanol") to "Spanish", listOf("french", "français", "francais") to "French",
        listOf("german", "deutsch") to "German", listOf("italian", "italiano") to "Italian",
        listOf("portuguese", "brazilian", "português") to "Portuguese", listOf("hindi") to "Hindi",
        listOf("japanese") to "Japanese", listOf("korean") to "Korean", listOf("chinese", "mandarin") to "Chinese",
        listOf("arabic") to "Arabic", listOf("russian") to "Russian", listOf("dutch") to "Dutch", listOf("turkish") to "Turkish",
    )

    /** An empty entry has no neutral form (Hindi's "I love you"): quiet. */
    private val phrases: Map<String, List<String>> = mapOf(
        "hello" to listOf("hola", "bonjour", "hallo", "ciao", "olá", "नमस्ते", "こんにちは", "안녕하세요", "你好", "مرحبا", "привет", "hallo", "merhaba"),
        "thank you" to listOf("gracias", "merci", "danke", "grazie", "obrigado", "धन्यवाद", "ありがとう", "감사합니다", "谢谢", "شكرا", "спасибо", "dank je", "teşekkürler"),
        "thank you so much" to listOf("muchas gracias", "merci beaucoup", "vielen Dank", "grazie mille", "muito obrigado", "बहुत धन्यवाद", "本当にありがとう", "정말 감사합니다", "非常感谢", "شكرا جزيلا", "большое спасибо", "heel erg bedankt", "çok teşekkürler"),
        "please" to listOf("por favor", "s'il vous plaît", "bitte", "per favore", "por favor", "कृपया", "お願いします", "부탁합니다", "请", "من فضلك", "пожалуйста", "alsjeblieft", "lütfen"),
        "sorry" to listOf("lo siento", "désolé", "Entschuldigung", "scusa", "desculpa", "माफ़ कीजिए", "ごめんなさい", "미안해요", "对不起", "آسف", "извините", "sorry", "özür dilerim"),
        "excuse me" to listOf("disculpe", "excusez-moi", "Entschuldigung", "mi scusi", "com licença", "सुनिए", "すみません", "실례합니다", "打扰一下", "عفوا", "извините", "pardon", "affedersiniz"),
        "good morning" to listOf("buenos días", "bonjour", "guten Morgen", "buongiorno", "bom dia", "सुप्रभात", "おはようございます", "좋은 아침이에요", "早上好", "صباح الخير", "доброе утро", "goedemorgen", "günaydın"),
        "good evening" to listOf("buenas tardes", "bonsoir", "guten Abend", "buonasera", "boa noite", "शुभ संध्या", "こんばんは", "좋은 저녁이에요", "晚上好", "مساء الخير", "добрый вечер", "goedenavond", "iyi akşamlar"),
        "good night" to listOf("buenas noches", "bonne nuit", "gute Nacht", "buonanotte", "boa noite", "शुभ रात्रि", "おやすみなさい", "안녕히 주무세요", "晚安", "تصبح على خير", "спокойной ночи", "welterusten", "iyi geceler"),
        "how are you" to listOf("¿cómo estás?", "comment ça va ?", "wie geht's?", "come stai?", "como vai?", "आप कैसे हैं?", "お元気ですか？", "잘 지내세요?", "你好吗？", "كيف حالك؟", "как дела?", "hoe gaat het?", "nasılsın?"),
        "i love you" to listOf("te quiero", "je t'aime", "ich liebe dich", "ti amo", "eu te amo", "", "愛してる", "사랑해요", "我爱你", "أحبك", "я тебя люблю", "ik hou van je", "seni seviyorum"),
        "goodbye" to listOf("adiós", "au revoir", "auf Wiedersehen", "arrivederci", "adeus", "अलविदा", "さようなら", "안녕히 가세요", "再见", "مع السلامة", "до свидания", "tot ziens", "hoşça kal"),
        "see you later" to listOf("hasta luego", "à plus tard", "bis später", "a dopo", "até logo", "फिर मिलेंगे", "またね", "나중에 봐요", "回头见", "أراك لاحقا", "до встречи", "tot later", "sonra görüşürüz"),
        "yes" to listOf("sí", "oui", "ja", "sì", "sim", "हाँ", "はい", "네", "是的", "نعم", "да", "ja", "evet"),
        "no" to listOf("no", "non", "nein", "no", "não", "नहीं", "いいえ", "아니요", "不是", "لا", "нет", "nee", "hayır"),
        "you're welcome" to listOf("de nada", "de rien", "gern geschehen", "prego", "de nada", "कोई बात नहीं", "どういたしまして", "천만에요", "不客气", "عفوا", "пожалуйста", "graag gedaan", "rica ederim"),
        "cheers" to listOf("¡salud!", "santé !", "prost!", "salute!", "saúde!", "चीयर्स", "乾杯", "건배", "干杯", "في صحتك", "за здоровье!", "proost!", "şerefe!"),
        "happy birthday" to listOf("feliz cumpleaños", "joyeux anniversaire", "alles Gute zum Geburtstag", "buon compleanno", "feliz aniversário", "जन्मदिन मुबारक", "お誕生日おめでとう", "생일 축하해요", "生日快乐", "عيد ميلاد سعيد", "с днём рождения", "gefeliciteerd met je verjaardag", "doğum günün kutlu olsun"),
        "congratulations" to listOf("felicidades", "félicitations", "herzlichen Glückwunsch", "congratulazioni", "parabéns", "बधाई हो", "おめでとう", "축하해요", "恭喜", "مبروك", "поздравляю", "gefeliciteerd", "tebrikler"),
        "good luck" to listOf("buena suerte", "bonne chance", "viel Glück", "buona fortuna", "boa sorte", "शुभकामनाएँ", "頑張って", "행운을 빌어요", "祝你好运", "حظا سعيدا", "удачи", "succes", "iyi şanslar"),
        "nice to meet you" to listOf("mucho gusto", "enchanté", "freut mich", "piacere", "prazer", "आपसे मिलकर खुशी हुई", "はじめまして", "만나서 반가워요", "很高兴认识你", "تشرفت بمعرفتك", "приятно познакомиться", "leuk je te ontmoeten", "tanıştığıma memnun oldum"),
        "i miss you" to listOf("te extraño", "tu me manques", "ich vermisse dich", "mi manchi", "sinto sua falta", "", "会いたい", "보고 싶어요", "我想你", "اشتقت إليك", "я скучаю по тебе", "ik mis je", "seni özledim"),
        "where is the bathroom" to listOf("¿dónde está el baño?", "où sont les toilettes ?", "wo ist die Toilette?", "dov'è il bagno?", "onde fica o banheiro?", "बाथरूम कहाँ है?", "トイレはどこですか？", "화장실이 어디예요?", "洗手间在哪里？", "أين الحمام؟", "где туалет?", "waar is het toilet?", "tuvalet nerede?"),
        "how much is this" to listOf("¿cuánto cuesta?", "combien ça coûte ?", "wie viel kostet das?", "quanto costa?", "quanto custa?", "यह कितने का है?", "いくらですか？", "이거 얼마예요?", "这个多少钱？", "بكم هذا؟", "сколько это стоит?", "hoeveel kost dit?", "bu ne kadar?"),
        "the bill please" to listOf("la cuenta, por favor", "l'addition, s'il vous plaît", "die Rechnung, bitte", "il conto, per favore", "a conta, por favor", "बिल दीजिए", "お会計をお願いします", "계산서 주세요", "请结账", "الحساب من فضلك", "счёт, пожалуйста", "de rekening, alstublieft", "hesap lütfen"),
        "i don't understand" to listOf("no entiendo", "je ne comprends pas", "ich verstehe nicht", "non capisco", "não entendo", "मुझे समझ नहीं आया", "わかりません", "이해가 안 돼요", "我不明白", "لا أفهم", "я не понимаю", "ik begrijp het niet", "anlamıyorum"),
        "do you speak english" to listOf("¿hablas inglés?", "parlez-vous anglais ?", "sprechen Sie Englisch?", "parli inglese?", "você fala inglês?", "क्या आप अंग्रेज़ी बोलते हैं?", "英語を話せますか？", "영어 하세요?", "你会说英语吗？", "هل تتكلم الإنجليزية؟", "вы говорите по-английски?", "spreekt u Engels?", "İngilizce biliyor musunuz?")
    )
    private val aliases: Map<String, String> = mapOf(
        "hi" to "hello", "hey" to "hello", "thanks" to "thank you", "thx" to "thank you", "ty" to "thank you",
        "thanks so much" to "thank you so much", "thank you very much" to "thank you so much", "thanks a lot" to "thank you so much",
        "bye" to "goodbye", "good bye" to "goodbye", "goodnight" to "good night", "gn" to "good night", "gm" to "good morning",
        "how are u" to "how are you", "how r u" to "how are you", "ily" to "i love you", "love you" to "i love you",
        "see you" to "see you later", "see ya" to "see you later", "cya" to "see you later", "sorry!" to "sorry",
        "your welcome" to "you're welcome", "youre welcome" to "you're welcome", "no problem" to "you're welcome",
        "happy bday" to "happy birthday", "hbd" to "happy birthday", "congrats" to "congratulations",
        "where's the bathroom" to "where is the bathroom", "where is the toilet" to "where is the bathroom",
        "the check please" to "the bill please", "check please" to "the bill please", "bill please" to "the bill please",
        "miss you" to "i miss you", "i dont understand" to "i don't understand", "do you speak english?" to "do you speak english",
    )

    private val pattern: Regex by lazy {
        val langs = languages.flatMap { it.first }.joinToString("|")
        val say = """(?:how\s+(?:do|would)\s+(?:you|u|i)\s+say\s+|what(?:'s|s|\s+is)\s+|translate\s+|say\s+)?"""
        Regex("""(?<![\w'])""" + say + """["“']?([a-z' ?!]{2,30}?)["”']?\s+(?:in|to|into)\s+(""" + langs + """)\??\s?$""",
              RegexOption.IGNORE_CASE)
    }

    fun phraseIn(text: String): Smart.Conversions? {
        val m = pattern.find(text) ?: return null
        val phrase = m.groupValues[1].lowercase().trim()
        val lang = m.groupValues[2].lowercase()
        val index = languages.indexOfFirst { lang in it.first }.takeIf { it >= 0 } ?: return null
        // "ok thank you in spanish": the phrase is the longest known tail.
        val words = phrase.split(" ").filter { it.isNotEmpty() }
        for (start in words.indices) {
            val tail = words.drop(start).joinToString(" ")
            val key = if (phrases.containsKey(tail)) tail else aliases[tail] ?: ""
            val row = phrases[key] ?: continue
            val said = row.getOrNull(index)?.takeIf { it.isNotEmpty() } ?: return null
            val whole = m.value.trim()
            val source = if (start == 0) whole else whole.substring(maxOf(0, whole.lowercase().indexOf(tail)))
            return Smart.Conversions(source, listOf(said), hows = listOf(Smart.Insertion.REPLACE))
        }
        return null
    }
}
