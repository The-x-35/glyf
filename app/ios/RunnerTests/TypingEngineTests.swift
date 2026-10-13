import XCTest

/// Runs shared/typing/golden-cases.json — the same cases the Android engine's
/// JUnit suite runs — plus the pieces underneath.
final class TypingEngineTests: XCTestCase {

    private static let sharedDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // RunnerTests
        .deletingLastPathComponent()          // ios
        .deletingLastPathComponent()          // app
        .deletingLastPathComponent()          // repo
        .appendingPathComponent("shared/typing")

    private let today = 20_000

    private func goldenTrie() throws -> GlydTrie {
        let path = Self.sharedDir.appendingPathComponent("golden.glyd").path
        return try XCTUnwrap(GlydTrie.mapped(path: path), "compile it: python3 tools/build_dictionary.py shared/typing/golden.combined shared/typing/golden.glyd")
    }

    func testGoldenCases() throws {
        let failures = try runCases(Self.sharedDir.appendingPathComponent("golden-cases.json"), trie: try goldenTrie())
        XCTAssert(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    /// The same expectations on the dictionary the keyboards ship.
    func testRealDictionaryCases() throws {
        let repo = Self.sharedDir.deletingLastPathComponent().deletingLastPathComponent()
        let dict = repo.appendingPathComponent("app/dict/en.glyd").path
        guard let trie = GlydTrie.mapped(path: dict) else { throw XCTSkip("app/dict/en.glyd not built") }
        let failures = try runCases(Self.sharedDir.appendingPathComponent("real-cases.json"), trie: trie,
                                    packs: repo.appendingPathComponent("app/assets/vocab/packs.json"))
        XCTAssert(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    /// A word typed in full offers only its completions and its own
    /// apostrophe forms, never its neighbours (Arpit, 2026-10-07: suggestions
    /// should be "crazy helpful"; "noon" offered moon, non, boon).
    /// "I" at the start of sentences, again and again, never teaches a lone
    /// "i" (2026-10-14: the third sentence-start "I" was learned as "i", and
    /// "and i" was never fixed again). A lexicon that already learned "i"
    /// that way, or a word with a line separator in it, heals on load.
    func testSentenceStartIDoesNotTeachLowercaseI() throws {
        let engine = TypingEngine(base: try goldenTrie())
        for _ in 0..<4 {
            _ = engine.commit(word: "I", previous: nil, autoCapitalized: true, policy: .all, today: today)
        }
        XCTAssertEqual(engine.suggestions(typed: "i", previous: nil, sentenceStart: false, today: today).autocorrect, "I")

        let healed = PersonalLexicon(json: ["words": [
            ["k": "i", "f": "i", "c": 8.0, "t": 8, "d": today],
            ["k": "hi\u{2028}there", "f": "Hi\u{2028}there", "c": 1.0, "t": 1, "d": today],
        ]])
        XCTAssertEqual(healed.word("i")?.form, "I")
        XCTAssertNil(healed.word("hi\u{2028}there"))
        XCTAssertFalse(TypingEngine.isLearnable("Hi\u{2028}there"))
        let fresh = TypingEngine(base: try goldenTrie())
        fresh.replacePersonal(healed)
        XCTAssertEqual(fresh.suggestions(typed: "i", previous: nil, sentenceStart: false, today: today).autocorrect, "I")
    }

    func testAKnownWordOffersCompletionsNotNeighbours() throws {
        let repo = Self.sharedDir.deletingLastPathComponent().deletingLastPathComponent()
        guard let trie = GlydTrie.mapped(path: repo.appendingPathComponent("app/dict/en.glyd").path) else {
            throw XCTSkip("app/dict/en.glyd not built")
        }
        let engine = TypingEngine(base: trie)
        let noon = engine.suggestions(typed: "noon", previous: "at", sentenceStart: false)
        XCTAssertTrue(noon.known)
        XCTAssertFalse(noon.alternatives.contains("moon"), "\(noon.alternatives)")
        let the = engine.suggestions(typed: "the", previous: "at", sentenceStart: false)
        XCTAssertTrue(the.alternatives.allSatisfy { $0.lowercased().hasPrefix("the") }, "\(the.alternatives)")
        let its = engine.suggestions(typed: "its", previous: "think", sentenceStart: false)
        XCTAssertTrue(its.alternatives.contains("it's"), "\(its.alternatives)")
        let lol = engine.suggestions(typed: "lol", previous: nil, sentenceStart: true)
        XCTAssertFalse(lol.alternatives.contains("lot"), "\(lol.alternatives)")
        // A slip still gets its fix and the words near it.
        let thier = engine.suggestions(typed: "thier", previous: "at", sentenceStart: false)
        XCTAssertEqual(thier.autocorrect, "their")
        XCTAssertFalse(thier.alternatives.isEmpty)
    }

    /// Both engines on the same inputs, line for line (off unless asked for):
    /// TEST_RUNNER_GLYF_PARITY_DIR holds in.tsv (previous word, typed, "1" at
    /// a sentence start, the word before the previous); this writes swift.tsv and the JUnit TypingParity
    /// writes kotlin.tsv from the same file. They must match.
    func testParityDump() throws {
        guard let dir = ProcessInfo.processInfo.environment["GLYF_PARITY_DIR"],
              let input = try? String(contentsOfFile: dir + "/in.tsv", encoding: .utf8) else {
            throw XCTSkip("GLYF_PARITY_DIR/in.tsv not given")
        }
        let repo = Self.sharedDir.deletingLastPathComponent().deletingLastPathComponent()
        let trie = try XCTUnwrap(GlydTrie.mapped(path: repo.appendingPathComponent("app/dict/en.glyd").path))
        let engine = TypingEngine(base: trie)
        var out = ""
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) where !line.isEmpty {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) + ["", "", "", ""]
            let prev = parts[0].isEmpty ? nil : parts[0]
            let prev2 = parts[3].isEmpty ? nil : parts[3]
            if parts[1].isEmpty {
                out += engine.predictions(previous: prev, beforePrevious: prev2, policy: .all, today: today)
                    .joined(separator: ",") + "\n"
                continue
            }
            let s = engine.suggestions(typed: parts[1], previous: prev, beforePrevious: prev2,
                                       sentenceStart: parts[2] == "1", policy: .all, today: today)
            out += (s.autocorrect ?? "-") + "\t" + s.alternatives.joined(separator: ",") + "\t" + (s.known ? "known" : "") + "\n"
        }
        try out.write(toFile: dir + "/swift.tsv", atomically: true, encoding: .utf8)
    }

    /// Pack words and phrases by id, split the way the keyboards load them.
    private func packContent(_ url: URL?, ids: [String]) throws -> (words: [String], phrases: [String]) {
        guard let url, !ids.isEmpty else { return ([], []) }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var words: [String] = [], phrases: [String] = []
        for pack in root["packs"] as? [[String: Any]] ?? [] where ids.contains(pack["id"] as? String ?? "") {
            for entry in pack["words"] as? [String] ?? [] {
                words += entry.split(separator: " ").map(String.init)
                if entry.contains(" ") { phrases.append(entry) }
            }
            for phrase in pack["phrases"] as? [String] ?? [] {
                words += phrase.split(separator: " ").map(String.init)
                phrases.append(phrase)
            }
        }
        return (words, phrases)
    }

    private func runCases(_ file: URL, trie: GlydTrie, packs: URL? = nil) throws -> [String] {
        let data = try Data(contentsOf: file)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rowPitch = Float(root["rowPitch"] as? Double ?? 1.44)
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        var failures: [String] = []

        for c in cases {
            let name = c["name"] as? String ?? "?"
            let engine = TypingEngine(base: trie, geometry: KeyGeometry(rowPitch: rowPitch))
            let state = c["state"] as? [String: Any] ?? [:]
            var lexicon = PersonalLexicon()
            for item in state["learned"] as? [[Any]] ?? [] {
                let form = item[0] as! String
                for _ in 0..<(item[1] as! Int) { lexicon.commit(form, previous: nil, today: today) }
            }
            for item in state["pairs"] as? [[Any]] ?? [] {
                for _ in 0..<(item[2] as! Int) { lexicon.commit(item[1] as! String, previous: item[0] as? String, today: today) }
            }
            for form in state["kept"] as? [String] ?? [] { lexicon.keep(form, today: today) }
            for item in state["rejected"] as? [[String]] ?? [] {
                // A revert keeps the typed word too; without "kept" the case tests the block alone.
                if state["kept"] != nil { lexicon.revert(typed: item[0], correction: item[1], today: today) }
                else { lexicon.reject(typed: item[0], correction: item[1]) }
            }
            // Removed in the app's "My words".
            for form in state["forgotten"] as? [String] ?? [] { lexicon.forget(form) }
            for form in state["addedWords"] as? [String] ?? [] { lexicon.add(form, today: today) }
            engine.replacePersonal(lexicon)
            engine.setPackWords(state["packWords"] as? [String] ?? [])
            engine.setContacts(state["contacts"] as? [String] ?? [])
            engine.setPackPhrases(state["packPhrases"] as? [String] ?? [])
            if let ids = state["packs"] as? [String] {
                let content = try packContent(packs, ids: ids)
                engine.setPackWords(content.words)
                engine.setPackPhrases(content.phrases)
            }

            let policyJSON = c["policy"] as? [String: Bool] ?? [:]
            var policy = TypingEngine.Policy.all
            if policyJSON["autocorrect"] == false { policy.remove(.autocorrect) }
            if policyJSON["suggestions"] == false { policy.remove(.suggestions) }
            if policyJSON["learning"] == false { policy.remove(.learning) }

            let typed = c["typed"] as? String ?? ""
            let previous = c["previous"] as? String
            let beforePrevious = c["beforePrevious"] as? String
            let expect = c["expect"] as? [String: Any] ?? [:]

            if typed.isEmpty {
                let predictions = engine.predictions(previous: previous, beforePrevious: beforePrevious,
                                                     policy: policy, today: today)
                for word in expect["predictionsInclude"] as? [String] ?? [] where !predictions.contains(word) {
                    failures.append("\(name): predictions \(predictions) lack \(word)")
                }
                continue
            }

            let touches = (c["touches"] as? [[Double]])?.map { t -> (Float, Float)? in (Float(t[0]), Float(t[1])) }
            let s = engine.suggestions(typed: typed, touches: touches, previous: previous,
                                       beforePrevious: beforePrevious,
                                       sentenceStart: c["sentenceStart"] as? Bool ?? false,
                                       policy: policy, today: today)
            if expect.keys.contains("autocorrect") {
                let want = expect["autocorrect"] as? String
                if s.autocorrect != want {
                    failures.append("\(name): autocorrect \(s.autocorrect ?? "nil") ≠ \(want ?? "nil") (alternatives \(s.alternatives))")
                }
            }
            for word in expect["autocorrectNot"] as? [String] ?? [] where s.autocorrect == word {
                failures.append("\(name): autocorrected to \(word)")
            }
            if let known = expect["known"] as? Bool, known != s.known {
                failures.append("\(name): known \(s.known) ≠ \(known)")
            }
            let offered = s.alternatives + [s.autocorrect].compactMap { $0 }
            for word in expect["alternativesInclude"] as? [String] ?? [] where !offered.contains(word) {
                failures.append("\(name): \(offered) lack \(word)")
            }
            for word in expect["alternativesExclude"] as? [String] ?? [] where offered.contains(word) {
                failures.append("\(name): \(offered) include \(word)")
            }
            if let max = expect["alternativesMax"] as? Int, s.alternatives.count > max {
                failures.append("\(name): \(s.alternatives.count) alternatives > \(max)")
            }
            if let first = expect["alternativesFirst"] as? String, s.alternatives.first != first {
                failures.append("\(name): first alternative \(s.alternatives.first ?? "none") ≠ \(first)")
            }
        }
        return failures
    }

    func testBuiltTrieReadsLikeTheCompiledOne() throws {
        let trie = GlydTrie.build([
            .init(form: "Zomato", probability: 160),
            .init(form: "zoom", probability: 120),
            .init(form: "it's", probability: 200),
            .init(form: "its", probability: 180),
        ])
        let node = try XCTUnwrap(trie.node(forKey: "its"))
        XCTAssertEqual(trie.entryCount(node), 2)
        XCTAssertEqual(trie.form(trie.firstEntry(node)), "it's")
        let z = try XCTUnwrap(trie.node(forKey: "zomato"))
        XCTAssertEqual(trie.form(trie.firstEntry(z)), "Zomato")
        XCTAssertNotEqual(trie.flags(trie.firstEntry(z)) & GlydTrie.flagHasUpper, 0)
        XCTAssertEqual(trie.maxProbability(0), 200)
        XCTAssertNil(trie.node(forKey: "zz"))
    }

    func testCompiledDictionaryHasWhitelistsAndBigrams() throws {
        let trie = try goldenTrie()
        let dont = try XCTUnwrap(trie.node(forKey: "dont"))
        XCTAssertEqual(trie.form(trie.firstEntry(dont)), "don't")
        XCTAssertNotEqual(trie.flags(trie.firstEntry(dont)) & GlydTrie.flagWhitelist, 0)
        let thank = try XCTUnwrap(trie.node(forKey: "thank"))
        let next = trie.bigrams(trie.firstEntry(thank)).map { trie.form($0.target) }
        XCTAssertEqual(next, ["you"])
    }

    func testEditDistanceCountsASwapAsOne() {
        XCTAssertEqual(TypingText.editDistance(TypingText.scalars("teh"), TypingText.scalars("the")), 1)
        XCTAssertEqual(TypingText.editDistance(TypingText.scalars("arpit"), TypingText.scalars("armpit")), 1)
        XCTAssertEqual(TypingText.editDistance(TypingText.scalars("glyf"), TypingText.scalars("glyph")), 2)
    }

    func testKeysDropApostrophesAndCase() {
        XCTAssertEqual(TypingText.key("Don’t"), "dont")
        XCTAssertEqual(TypingText.key("Follow-up"), "followup")
        XCTAssertEqual(TypingText.base(UInt32(("É" as Unicode.Scalar).value)), UInt32(("e" as Unicode.Scalar).value))
        XCTAssertEqual(TypingText.matchCase(typed: "Teh", form: "the"), "The")
        XCTAssertEqual(TypingText.matchCase(typed: "Dont", form: "don't"), "Don't")
        XCTAssertEqual(TypingText.matchCase(typed: "pune", form: "Pune"), "Pune")
    }

    func testLearningAndForgetting() {
        var lexicon = PersonalLexicon()
        lexicon.commit("glyf", previous: nil, today: today)
        XCTAssertFalse(lexicon.isKnown("glyf"), "one commit could be a typo")
        lexicon.commit("glyf", previous: "try", today: today)
        XCTAssertTrue(lexicon.isKnown("glyf"))
        XCTAssertEqual(lexicon.probability("glyf", today: today) ?? 0, 111.3, accuracy: 0.5, "AOSP: ~111 after two uses")
        lexicon.commit("glyf", previous: nil, today: today)
        XCTAssertEqual(lexicon.probability("glyf", today: today) ?? 0, 119.9, accuracy: 0.5, "~120 after three")

        // Decay lowers the rank, never the learned status.
        XCTAssertLessThan(lexicon.probability("glyf", today: today + 400) ?? 0, 111)
        XCTAssertTrue(lexicon.isKnown("glyf"))

        lexicon.forget("glyf")
        XCTAssertFalse(lexicon.isKnown("glyf"))
        lexicon.commit("glyf", previous: nil, today: today)
        lexicon.commit("glyf", previous: nil, today: today)
        XCTAssertFalse(lexicon.isKnown("glyf"), "forgotten words aren't relearned")
    }

    func testRevertBlocksThePairAndUnlearnsTheCorrection() throws {
        let engine = TypingEngine(base: try goldenTrie())
        XCTAssertEqual(engine.suggestions(typed: "teh", previous: nil, sentenceStart: false, today: today).autocorrect, "the")
        engine.commit(word: "the", previous: nil, autoCapitalized: false, policy: .all, today: today)
        engine.revert(typed: "teh", correction: "the", today: today)
        let again = engine.suggestions(typed: "teh", previous: nil, sentenceStart: false, today: today)
        XCTAssertNil(again.autocorrect)
        XCTAssertTrue(again.known)
        XCTAssertNil(engine.personal.word("the"), "the correction's commit was taken back")
    }

    func testAutoCapitalizedFirstWordIsLearnedLowercase() throws {
        let engine = TypingEngine(base: try goldenTrie())
        engine.commit(word: "Hello", previous: nil, autoCapitalized: true, policy: .all, today: today)
        XCTAssertEqual(engine.personal.word("hello")?.form, "hello")
        engine.commit(word: "Arpit", previous: nil, autoCapitalized: true, policy: .all, today: today)
        XCTAssertEqual(engine.personal.word("arpit")?.form, "Arpit", "not a word in lowercase: a name")
    }

    func testNothingIsLearnedWhereLearningIsOff() throws {
        let engine = TypingEngine(base: try goldenTrie())
        engine.commit(word: "secretword", previous: nil, autoCapitalized: false, policy: [.suggestions], today: today)
        engine.commit(word: "4242424242424242", previous: nil, autoCapitalized: false, policy: .all, today: today)
        engine.commit(word: "me@glyf.so", previous: nil, autoCapitalized: false, policy: .all, today: today)
        XCTAssertNil(engine.personal.word("secretword"))
        XCTAssertNil(engine.personal.word("4242424242424242"))
        XCTAssertTrue(engine.personal.words.isEmpty)
    }

    func testLearnedWordsBecomeSearchable() throws {
        let engine = TypingEngine(base: try goldenTrie())
        for _ in 0..<3 { engine.commit(word: "Zomato", previous: nil, autoCapitalized: false, policy: .all, today: today) }
        let s = engine.suggestions(typed: "zomat", previous: nil, sentenceStart: false, today: today)
        XCTAssertTrue((s.alternatives + [s.autocorrect].compactMap { $0 }).contains("Zomato"), "\(s)")
    }

    func testDecodeIsFastEnough() throws {
        let engine = TypingEngine(base: try goldenTrie())
        measure {
            for word in ["teh", "helo", "tomorow", "meetign", "thnaks", "pleaes"] {
                _ = engine.suggestions(typed: word, previous: "the", sentenceStart: false, today: today)
            }
        }
    }
}
