import XCTest
@testable import Runner

/// A look at what the strip would show for everyday messages, as a table in
/// the test log (`grep '^PROBE|'`), off unless asked for:
/// TEST_RUNNER_GLYF_STRIP_PROBE=1. The 2026-10-07 pass over these messages
/// found the gaps that became coin amounts, "usd to inr", sums in words,
/// city time, "until 5pm", the list maker and the emoji slot. Android's
/// StripEval is the engine-only cousin.
final class StripProbeTests: XCTestCase {
    func testProbe() throws {
        guard ProcessInfo.processInfo.environment["GLYF_STRIP_PROBE"] != nil else {
            throw XCTSkip("GLYF_STRIP_PROBE not set")
        }
        let shared = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/typing")
        let repo = shared.deletingLastPathComponent().deletingLastPathComponent()
        let trie = try XCTUnwrap(GlydTrie.mapped(path: repo.appendingPathComponent("app/dict/en.glyd").path))
        let engine = TypingEngine(base: trie)
        let fields = [
            VaultField(id: "n", kind: "name", label: "Name", value: "Alex Kim"),
            VaultField(id: "e", kind: "email", label: "Email", value: "alex@example.com"),
            VaultField(id: "p", kind: "phone", label: "Mobile", value: "+1 415 555 0134"),
            VaultField(id: "a", kind: "address", label: "Home", value: "123 Market St, San Francisco, CA 94103"),
            VaultField(id: "w", kind: "wallet", label: "Wallet address", value: "4j8FqYuNix7RfFgKmiRZnCE1acNnTarqm1SbZYdQZmFA"),
            VaultField(id: "l", kind: "link", label: "Website", value: "https://tryglyf.com"),
        ]
        let rates = Smart.RatesSnapshot(fiat: ["USD": 1, "INR": 83.5, "EUR": 0.92, "GBP": 0.79, "JPY": 150],
                                        crypto: ["SOL": 120, "BTC": 65000], local: "USD")
        let messages = [
            // plans and times
            "lets meet at 7", "dinner tomorrow at 8pm?", "call me in 20 mins", "see you in 2 hours", "flight lands 6:45am",
            "what time is it in tokyo", "9am pst works?", "next friday?", "on 25 dec", "lunch at noon", "gym at 6 then dinner",
            "meeting moved to thursday 3pm", "my bday is 14 feb", "how many days till christmas", "days until 20 nov",
            "how long until 5pm", "in 45 minutes", "3pm est", "7pm ist for me", "what date is next monday", "tmrw at 10",
            // money
            "i owe you 450", "split 1200 3 ways", "its $45 each", "20% tip on 85", "paid 2.5k", "rent is 1500 + 200",
            "100 usd to inr", "5 eur", "£40", "it was 2000 yen", "half of 350", "double it 25", "we spent 1,250 total",
            "that's 15% off 80", "3 for $10", "venmo me 20", "$sol", "$btc", "1 sol", "0.5 btc",
            // maths
            "12*8", "2+2", "15% of 200", "sqrt 81", "1/3 of 90", "7 x 6", "100/8", "2^10", "40 of 60",
            // units
            "6 ft 2", "its 35 degrees", "100 km", "5 miles", "2 litres", "70 kg", "180 cm", "2m", "10k run", "5k",
            // details
            "my number is", "send it to my email", "whats your address", "my upi is", "here's my address",
            "email me at", "wallet address is", "my site is", "call me on", "im alex", "this is alex kim",
            // links and phones
            "https://youtu.be/x9?si=abc123", "check https://www.amazon.com/dp/B0?tag=xyz&ref=1", "9876543210", "+1 415 555 0134",
            "415 555 0134", "track 1Z999AA10123456784", "my flight is AI 101", "AA 2345",
            // questions, replies, slang
            "wyd", "omw", "brb", "k", "lol", "idk", "tbh", "gonna", "wanna", "nah", "yup", "ya", "hbu", "ty", "np", "gm", "gn",
            "how far is the moon", "capital of france", "define serendipity", "synonym for happy", "spell necessary",
            "what should i reply", "whats 20 celsius", "weather today", "roll a dice", "flip a coin", "pick one: pizza or sushi",
            // emoji moments
            "happy birthday!!", "congrats", "love you", "so sad", "this is fire", "lmao", "good night", "miss you", "thank you so much",
            // typos
            "i hsven", "teh", "recieve", "definately", "tommorow", "wich", "thier", "alot", "seperate", "accomodate", "occured",
            "i think thats", "see you tommorow", "im comming", "wat r u doing", "cant wait", "ill be there", "dont worry",
            "lets go", "youre right", "its fine", "were here", "ive got it", "shouldnt", "wouldve",
            // names, places, hinglish
            "hi arpit", "tom said", "going to bangalore", "kya kar rahe ho", "acha", "haan bhai", "chalo",
            // sentence starts and predictions after a space
            "I ", "I am ", "see you ", "thank you ", "happy ", "good ", "how are ", "let me ", "on my ", "talk to you ",
            "ok see you at ", "the meeting is at ", "send me your ", "my address is ", "call me ",
            // lists
            "1. milk", "- eggs", "todo: call mom", "shopping: ", "grocery list:",
            // formatting / style
            "**bold**", "make this bold", "ALL CAPS please", "hello world",
        ]
        print("PROBE|message|chip|typed→fix|alternatives|predictions")
        for text in messages {
            var row = text.replacingOccurrences(of: "|", with: "/")
            let chip = Smart.chip(for: text, fields: fields, paste: nil, field: .none, rates: rates,
                                  ownWallet: nil, indianGrouping: false, region: "US", linkContext: text)
            let chipText = chip.map { String(describing: $0).replacingOccurrences(of: "\n", with: " ") } ?? "-"
            row += "|" + String(chipText.prefix(150))
            let word = WordTracker.currentWord(beforeContext: text)
            let previous = WordTracker.previousWord(beforeContext: text)
            let twoBack = WordTracker.wordBeforePrevious(beforeContext: text)
            if word.isEmpty {
                row += "|-|-|"
                if text.hasSuffix(" "), let previous {
                    row += engine.predictions(previous: previous, beforePrevious: twoBack).joined(separator: ", ")
                }
            } else {
                let start = previous == nil
                let s = engine.suggestions(typed: word, previous: previous, beforePrevious: twoBack, sentenceStart: start)
                row += "|\(word)→\(s.autocorrect ?? (s.known ? "(known)" : "(unknown)"))|\(s.alternatives.joined(separator: ", "))|"
            }
            print("PROBE|" + row)
        }
    }
}
