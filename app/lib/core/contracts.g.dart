// GENERATED from shared/contracts — do not edit (tools/gen_contracts.mjs)

class IntentOrigin {
  final String source;
  final String? glyfId;
  final String rawText;
  const IntentOrigin({required this.source, this.glyfId, required this.rawText});
  factory IntentOrigin.fromJson(Map<String, dynamic> j) => IntentOrigin(
        source: j['source'] as String,
        glyfId: j['glyfId'] as String?,
        rawText: j['rawText'] as String,
      );
}

class IntentRisk {
  final double score;
  final List<String> flags;
  const IntentRisk({required this.score, required this.flags});
  factory IntentRisk.fromJson(Map<String, dynamic> j) => IntentRisk(
        score: j['score'] as double,
        flags: (j['flags'] as List).cast<String>(),
      );
}

class GlyfIntentContract {
  final String id;
  final int version;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String kind;
  final IntentOrigin origin;
  final Map<String, String> payload;
  final IntentRisk risk;
  final String nonce;
  const GlyfIntentContract({required this.id, required this.version, required this.createdAt, required this.expiresAt, required this.kind, required this.origin, required this.payload, required this.risk, required this.nonce});
  factory GlyfIntentContract.fromJson(Map<String, dynamic> j) => GlyfIntentContract(
        id: j['id'] as String,
        version: j['version'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        kind: j['kind'] as String,
        origin: IntentOrigin.fromJson(j['origin'] as Map<String, dynamic>),
        payload: (j['payload'] as Map).cast<String, String>(),
        risk: IntentRisk.fromJson(j['risk'] as Map<String, dynamic>),
        nonce: j['nonce'] as String,
      );
}

class ResultError {
  final String code;
  final String message;
  const ResultError({required this.code, required this.message});
  factory ResultError.fromJson(Map<String, dynamic> j) => ResultError(
        code: j['code'] as String,
        message: j['message'] as String,
      );
}

class GlyfResultContract {
  final String intentId;
  final String status;
  final Map<String, String> payload;
  final ResultError? error;
  final DateTime completedAt;
  const GlyfResultContract({required this.intentId, required this.status, required this.payload, this.error, required this.completedAt});
  factory GlyfResultContract.fromJson(Map<String, dynamic> j) => GlyfResultContract(
        intentId: j['intentId'] as String,
        status: j['status'] as String,
        payload: (j['payload'] as Map).cast<String, String>(),
        error: j['error'] == null ? null : ResultError.fromJson(j['error'] as Map<String, dynamic>),
        completedAt: DateTime.parse(j['completedAt'] as String),
      );
}
