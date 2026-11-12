/// The group pot the person saved (shared settings `nearPot`): a Sputnik
/// DAO on NEAR, like trip.sputnik-dao.near. The keyboard reads it for a pot
/// chip that names no pot (docs/NEAR-SPEC.md, Which pot).
abstract final class NearPot {
  /// The settings key the keyboards read.
  static const key = 'nearPot';

  static const suffix = '.sputnik-dao.near';

  /// What's said when the text isn't a Sputnik DAO (the server's own words).
  static const invalid = 'A pot is a Sputnik DAO, like trip.sputnik-dao.near';

  /// [text] as it is saved: trimmed and lowercase, and a bare DAO name
  /// ("trip") made whole. Empty clears it. Null when it isn't a Sputnik DAO
  /// account: NEAR names are lowercase letters and digits, parts joined by
  /// "-" or "_", 64 characters at most in all.
  static String? normalize(String text) {
    var name = text.trim().toLowerCase();
    if (name.isEmpty) return '';
    if (!name.contains('.')) name = '$name$suffix';
    if (!name.endsWith(suffix) || name.length > 64) return null;
    final dao = name.substring(0, name.length - suffix.length);
    return RegExp(r'^[a-z0-9]+([-_][a-z0-9]+)*$').hasMatch(dao) ? name : null;
  }
}
