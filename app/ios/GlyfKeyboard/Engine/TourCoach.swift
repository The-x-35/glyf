import Foundation

/// The website's coach (site/components/chat/scenarios.ts) on the real
/// keyboard. The app's tour says which chat and step it is on; this reads
/// what the keyboard is showing and names the one thing to tap next, with
/// the same words the website uses. Nil means nothing to point at: the
/// friend is typing, the app is pointing (a bubble, Send), or the keyboard
/// is busy. Pure logic, so it can be unit tested.
enum TourCoach {

    struct Coach: Equatable {
        /// An accessibility identifier. A trailing "*" means the topmost
        /// visible view whose identifier starts with the rest.
        let target: String
        let label: String
    }

    enum SearchView: Equatable {
        case landing(rows: Int)
        case typing
        case loading
        case results(Int)
    }

    enum Panel: Equatable {
        case none
        /// `tab` is the tab's identifier: "search", "youtube" or "maps".
        case search(tab: String, view: SearchView, query: String)
        case vault
        /// The g menu's own grid of tools.
        case menu
        case act(working: Bool, options: Bool)
        case tones
        case translate(ready: Bool, target: String?)
        /// Anything else that is open, and the control that closes it.
        case other(close: String)
    }

    struct State {
        var step: String
        var text: String
        var panel: Panel = .none
        var chip: Smart.Chip?
        var suggestions: [String] = []
        var fields: [VaultField] = []
        /// Letters holding the vault and translate, if any.
        var vaultKey: String?
        var translateKey: String?
        /// Tools showing on the strip right now (people can move them).
        var stripTools: Set<String> = ["search", "vault", "translate"]
        /// The tour copied the address from the chat, so a paste chip now
        /// holds it (a keyboard cannot read the clipboard to check).
        var copied = false
    }

    /// While a step is being coached the strip only offers what that step is
    /// about: any other chip would cover the tool the coach points at.
    /// Kinds: "calc", "vault:<kind>", "paste", "pay", "action", "event", "booking".
    static func allowsChip(_ kind: String, step: String, copied: Bool = false) -> Bool {
        switch step {
        case "mom:0": return kind == "vault:address"
        case "semi:0": return kind == "pay" || (kind == "paste" && copied)
        case "zoya:0": return kind == "calc"
        case "zoya:1": return kind == "vault:wallet"
        default: return false
        }
    }

    /// Opens a tool: from the strip when it is there, else through the g menu.
    private static func tool(_ s: State, _ id: String, _ label: String) -> Coach {
        if s.panel == .menu { return Coach(target: "shell:tile:\(id)", label: label) }
        if s.stripTools.contains(id) { return Coach(target: "toolbar:\(id)", label: label) }
        return Coach(target: "toolbar:glyf", label: "Tap g")
    }

    static func has(_ s: String, _ part: String) -> Bool {
        !part.isEmpty && s.range(of: part, options: .caseInsensitive) != nil
    }

    static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The search tab a step is about.
    static func searchTab(step: String) -> String? {
        switch step {
        case "sakshi:0": return "maps"
        case "kabir:0": return "youtube"
        case "kabir:1": return "search"
        default: return nil
        }
    }

    /// What the keyboard types into search for you, per step.
    static func searchQuery(step: String) -> String? {
        switch step {
        case "sakshi:0": return "coffee near me"
        case "kabir:0": return "road trip songs"
        case "kabir:1": return "sunset time today"
        default: return nil
        }
    }

    /// What the keyboard types into the field for you, given what is open.
    static func autotype(_ s: State) -> String? {
        if s.step == "sofia:0", case .translate = s.panel, s.text.isEmpty {
            return "see you tomorrow"
        }
        return nil
    }

    static func coach(_ s: State) -> Coach? {
        let text = s.text
        switch s.step {
        case "sakshi:0":
            return search(s, tab: "maps", label: "Maps") { $0.contains("📍") }

        case "mom:0":
            return vault(s, kind: "address")

        case "semi:0":
            if text.hasPrefix("💸") { return nil }
            if case .other(let close) = s.panel { return Coach(target: close, label: "Close") }
            if s.panel != .none { return nil }
            switch s.chip {
            // A copied address is the paste, with Send beside it.
            case .pay: return Coach(target: "strip:smart:extra|strip:smart", label: "Send")
            case .paste: return s.copied ? Coach(target: "strip:smart", label: "Paste") : nil
            default: return nil   // the chat points at the address to copy
            }

        case "neha:0":
            switch s.panel {
            case .act(let working, let options):
                if working { return nil }
                return options ? Coach(target: "act:option:work", label: "Professional") : nil
            case .tones:
                return Coach(target: "tones:professional", label: "Professional")
            case .none:
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { return nil }
                if polished(t) { return nil }
                return Coach(target: "key:space", label: "Hold glyf")
            default:
                return closer(s.panel)
            }

        case "zoya:0":
            if text.contains("59") { return nil }
            if s.panel != .none { return closer(s.panel) }
            if case .calc = s.chip { return Coach(target: "strip:smart", label: "Tap") }
            return text.isEmpty ? nil : Coach(target: "key:delete", label: "Delete")

        case "zoya:1":
            let wallet = s.fields.first { $0.kind == "wallet" }
            if let wallet, has(text, wallet.value) { return nil }
            if case .vault = s.panel, let wallet, let i = s.fields.firstIndex(of: wallet) {
                return Coach(target: "vault:card:\(i)", label: "Tap \(wallet.label)")
            }
            if s.panel != .none { return closer(s.panel) }
            if case .vault(let f) = s.chip, f.kind == "wallet" { return Coach(target: "strip:smart", label: "Tap") }
            if text.isEmpty || matches(text, #"wallet address is\s*$"#) { return nil }
            return Coach(target: "key:delete", label: "Delete")

        case "kabir:0":
            return search(s, tab: "youtube", label: "YouTube") { $0.contains("youtu") || $0.contains("🎥") || $0.contains("▶") }

        case "kabir:1":
            return search(s, tab: "search", label: "Google") { matches($0, #"\d{1,2}:\d{2}"#) }

        case "sofia:0":
            if has(text, "mañana") { return nil }
            if case .translate(let ready, let target) = s.panel {
                if ready { return Coach(target: "hud:replace", label: "Replace") }
                if target != nil, target != "Spanish", matches(text, #"^\s*see you tomorrow\s*$"#) {
                    return Coach(target: "hud:direction", label: "Spanish")
                }
                if text.isEmpty || matches(text, #"^\s*see you tomorrow\s*$"#) { return nil }
                return Coach(target: "key:delete", label: "Delete")
            }
            if let key = s.translateKey, s.panel == .none {
                return Coach(target: "key:\(key)", label: "Hold \(key.uppercased())")
            }
            if s.panel != .none && s.panel != .menu { return closer(s.panel) }
            return tool(s, "translate", "Translate")

        default:
            return nil
        }
    }

    /// The website's "absolutely / sure thing" check, for a rewrite that
    /// came from a model: anything that is no longer the messy draft.
    static func polished(_ t: String) -> Bool {
        let s = t.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return !s.isEmpty && s != "ya ill send it by 6 dont worry" && !s.contains("dont worry")
    }

    private static func closer(_ panel: Panel) -> Coach? {
        switch panel {
        case .none: return nil
        case .search: return Coach(target: "search:close", label: "Close")
        case .vault, .menu: return Coach(target: "toolbar:close", label: "Close")
        case .act(let working, _): return working ? nil : Coach(target: "toolbar:close", label: "Close")
        case .tones: return Coach(target: "tones:close", label: "Close")
        case .translate: return Coach(target: "hud:close", label: "Close")
        case .other(let close): return Coach(target: close, label: "Close")
        }
    }

    private static func search(_ s: State, tab: String, label: String, done: (String) -> Bool) -> Coach? {
        if done(s.text) { return nil }
        guard case .search(let open, let view, let query) = s.panel else {
            if s.panel != .none && s.panel != .menu { return closer(s.panel) }
            return tool(s, "search", "Search")
        }
        if open != tab { return Coach(target: "search:tab:\(tab)", label: label) }
        switch view {
        case .results(let n): return n > 0 ? Coach(target: "search:card:*", label: "Tap to share") : nil
        case .loading: return nil
        case .typing, .landing:
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                return Coach(target: "search:go", label: "Search")
            }
            return nil   // the keyboard is typing the query
        }
    }

    private static func vault(_ s: State, kind: String) -> Coach? {
        let field = s.fields.first { $0.kind == kind }
        if let field, has(s.text, field.value) { return nil }
        if case .vault = s.panel {
            guard let field, let i = s.fields.firstIndex(of: field) else { return nil }
            return Coach(target: "vault:card:\(i)", label: "Tap \(field.label)")
        }
        if case .vault(let f) = s.chip, f.kind == kind {
            return Coach(target: "strip:smart", label: "Tap")
        }
        guard field != nil else { return s.panel == .none ? nil : closer(s.panel) }
        if let key = s.vaultKey, s.panel == .none {
            return Coach(target: "key:\(key)", label: "Hold \(key.uppercased())")
        }
        if s.panel != .none && s.panel != .menu { return closer(s.panel) }
        return tool(s, "vault", "Vault")
    }
}
