import Foundation

/// GENERATED from shared/contracts — do not edit (tools/gen_contracts.mjs)
/// Dates are ISO-8601 (IntentStore's encoder/decoder handle the strategy).

struct IntentOrigin: Codable, Equatable {
    var source: String
    var glyfId: String?
    var rawText: String

    init(source: String, glyfId: String? = nil, rawText: String) {
        self.source = source
        self.glyfId = glyfId
        self.rawText = rawText
    }
}

struct IntentRisk: Codable, Equatable {
    var score: Double
    var flags: [String]

    init(score: Double, flags: [String]) {
        self.score = score
        self.flags = flags
    }
}

struct Intent: Codable, Equatable {
    var id: String
    var version: Int
    var createdAt: Date
    var expiresAt: Date
    var kind: String
    var origin: IntentOrigin
    var payload: [String: String]
    var risk: IntentRisk
    var nonce: String

    init(id: String, version: Int, createdAt: Date, expiresAt: Date, kind: String, origin: IntentOrigin, payload: [String: String], risk: IntentRisk, nonce: String) {
        self.id = id
        self.version = version
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.kind = kind
        self.origin = origin
        self.payload = payload
        self.risk = risk
        self.nonce = nonce
    }
}

struct Result_Error: Codable, Equatable {
    var code: String
    var message: String

    init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

struct Result_: Codable, Equatable {
    var intentId: String
    var status: String
    var payload: [String: String]
    var error: Result_Error?
    var completedAt: Date

    init(intentId: String, status: String, payload: [String: String], error: Result_Error? = nil, completedAt: Date) {
        self.intentId = intentId
        self.status = status
        self.payload = payload
        self.error = error
        self.completedAt = completedAt
    }
}

typealias GlyfIntent = Intent
typealias GlyfResult = Result_
