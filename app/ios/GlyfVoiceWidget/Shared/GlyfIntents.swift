import AppIntents
import Foundation
import WidgetKit
#if !GLYF_WIDGET
import UIKit
#endif

// Glyf's actions for Shortcuts, Siri, Spotlight, the Action button and the
// widgets' buttons. Compiled into the app and the GlyfVoiceWidget
// extension: the widgets' buttons name these types, and LiveActivityIntent
// makes iOS run perform() in the app's process (launched in the background
// when it isn't running), where the Glyf session and the Google grant live.
// The extension's copy (GLYF_WIDGET) never runs.

// MARK: New Meet link

@available(iOS 17.0, *)
struct NewMeetLinkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "New Meet Link"
    static let description = IntentDescription("A Google Meet link of your own, copied and ready to paste.")

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        #if GLYF_WIDGET
        return .result(value: "", dialog: "")
        #else
        let link = try await GlyfMeetLink.make()
        await MainActor.run { UIPasteboard.general.string = link }
        GlyfWidgetData.write(GlyfWidgetData.MeetLink(url: link, at: Date()), GlyfWidgetData.meetFile)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: link, dialog: "\(GlyfWidgetData.shortLink(link))")
        #endif
    }
}

// MARK: Rewrite text

@available(iOS 17.0, *)
enum RewriteStyle: String, AppEnum {
    case basic, work, polite, shorter, emoji

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [RewriteStyle: DisplayRepresentation] = [
        .basic: "Basic", .work: "Professional", .polite: "Polite", .shorter: "Shorter", .emoji: "Emoji",
    ]
}

@available(iOS 17.0, *)
struct RewriteTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Rewrite Text"
    static let description = IntentDescription("Glyf rewrites your words: fixed, professional, polite, shorter or with emoji.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Style", default: .basic)
    var style: RewriteStyle

    static var parameterSummary: some ParameterSummary {
        Summary("Rewrite \(\.$text) as \(\.$style)")
    }

    init() {}
    init(text: String, style: RewriteStyle = .basic) {
        self.text = text
        self.style = style
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        #if GLYF_WIDGET
        return .result(value: "", dialog: "")
        #else
        let out = try await GlyfIntentAPI.rewrite(text, style: style.rawValue)
        return .result(value: out, dialog: "\(out)")
        #endif
    }
}

// MARK: Run a glyf

/// A glyf: one of the person's own (Build your own) or a built-in rewrite.
@available(iOS 17.0, *)
struct GlyfEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Glyf"
    static let defaultQuery = GlyfEntityQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    static let builtIn: [GlyfEntity] = [
        .init(id: "rewrite.polite", title: "Make it polite"),
        .init(id: "rewrite.tighten", title: "Tighten"),
        .init(id: "rewrite.professional", title: "Professional"),
        .init(id: "glyf.proofread", title: "Proofread"),
        .init(id: "rewrite.emoji", title: "Emoji-fy"),
        .init(id: "glyf.translate", title: "Translate"),
    ]

    /// Saved glyfs first (settings' customTitles), then the built-ins.
    static func all(settings: [String: Any]?) -> [GlyfEntity] {
        GlyfWidgetData.savedGlyfs(settings: settings).map { GlyfEntity(id: $0.id, title: $0.title) } + builtIn
    }
}

@available(iOS 17.0, *)
struct GlyfEntityQuery: EntityQuery, EntityStringQuery {
    init() {}

    private var all: [GlyfEntity] { GlyfEntity.all(settings: GlyfWidgetData.readObject("settings.json")) }

    func entities(for identifiers: [String]) async throws -> [GlyfEntity] {
        all.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [GlyfEntity] {
        all.filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [GlyfEntity] { all }
}

@available(iOS 17.0, *)
struct RunGlyfIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Glyf"
    static let description = IntentDescription("Runs one of your glyfs on some text and gives back what it wrote.")

    @Parameter(title: "Glyf")
    var glyf: GlyfEntity

    @Parameter(title: "Text", default: "", inputOptions: String.IntentInputOptions(multiline: true))
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$glyf) on \(\.$input)")
    }

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        #if GLYF_WIDGET
        return .result(value: "", dialog: "")
        #else
        if GlyfIntentParsing.asksForText(glyfId: glyf.id, input: input) {
            input = try await $input.requestValue("What should \(glyf.title) work on?")
        }
        let out = try await GlyfIntentAPI.runGlyf(glyf.id, input: input)
        return .result(value: out, dialog: "\(out)")
        #endif
    }
}

// MARK: Open places in Glyf

@available(iOS 17.0, *)
enum GlyfPlace: String, AppEnum {
    case wallet, ethereum, vault, build, glyfs

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Place"
    static let caseDisplayRepresentations: [GlyfPlace: DisplayRepresentation] = [
        .wallet: "Wallet", .ethereum: "Ethereum wallet", .vault: "Vault", .build: "Build your own", .glyfs: "My glyfs",
    ]

    var url: URL {
        switch self {
        case .wallet: return GlyfWidgetData.wallet
        case .ethereum: return GlyfWidgetData.evmWallet
        case .vault: return GlyfWidgetData.vault
        case .build: return GlyfWidgetData.build
        case .glyfs: return GlyfWidgetData.glyfs
        }
    }
}

@available(iOS 17.0, *)
struct OpenGlyfIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Glyf"
    static let description = IntentDescription("Opens Glyf on your wallet, vault or glyfs.")
    static let openAppWhenRun = true

    @Parameter(title: "Place", default: .wallet)
    var place: GlyfPlace

    init() {}
    init(place: GlyfPlace) { self.place = place }

    func perform() async throws -> some IntentResult {
        #if !GLYF_WIDGET
        let url = place.url
        await MainActor.run { GlyfBridge.shared.handleDeepLink(url) }
        #endif
        return .result()
    }
}

