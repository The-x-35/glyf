/// The Builder's Tools: what a glyf may use beyond the model, one switch
/// each. Ids match the server's (server/src/lib/buildertools.ts). Connecting
/// a tool is never done here: the row's Connect goes to the screen that owns
/// it (Connected tools, or Profile › Search for Nearby).
library;

enum ToolConnect { none, connectedTools, nearby }

class GlyfTool {
  const GlyfTool(this.id, this.title, this.brand, this.connect, this.tools);

  /// The server's switch id ("meet", "booking"…).
  final String id;
  final String title;

  /// A BrandMark id, or an icon name for the ones without a brand.
  final String brand;
  final ToolConnect connect;

  /// Registry tools it opens up.
  final List<String> tools;
}

abstract final class GlyfTools {
  static const all = [
    GlyfTool('meet', 'Google Meet', 'meet', ToolConnect.connectedTools, ['meet.new']),
    GlyfTool('booking', 'Booking link', 'booking', ToolConnect.connectedTools, ['booking.link']),
    GlyfTool('calendar', 'Calendar', 'calendar', ToolConnect.connectedTools, ['calendar.day']),
    GlyfTool('location', 'Location', 'location', ToolConnect.nearby, ['place.here']),
    GlyfTool('details', 'Your details', 'details', ToolConnect.none, []),
    GlyfTool('live', 'Live info', 'live', ToolConnect.none, []),
  ];

  /// Tools the PHONE answers before a run (the keyboard fetches each and
  /// sends it as `phone.<tool>`). Everything else runs on the server.
  static const phoneTools = {'meet.new', 'booking.link', 'calendar.day'};

  /// What a step's tool is called in "How it works".
  static const toolTitles = {
    'meet.new': 'Makes a new Google Meet link',
    'booking.link': 'Adds your booking link',
    'calendar.day': 'Reads your day',
    'place.here': 'Finds where you are',
  };

  static List<Map<String, dynamic>> _steps(Map<String, dynamic> def) =>
      ((def['steps'] as List?) ?? const []).whereType<Map>().map((s) => s.cast<String, dynamic>()).toList();

  /// The phone tools a glyf uses, in step order, each once.
  static List<String> phoneToolsOf(Map<String, dynamic> def) {
    final out = <String>[];
    for (final s in _steps(def)) {
      final tool = s['tool'];
      if (s['type'] == 'tool' && tool is String && phoneTools.contains(tool) && !out.contains(tool)) {
        out.add(tool);
      }
    }
    return out;
  }

  /// The switches a glyf uses: the server says (requires.connectors), and
  /// a glyf from before the Tools says nothing, so its steps are read.
  static Set<String> usedBy(Map<String, dynamic> def) {
    final used = <String>{};
    final known = all.map((t) => t.id).toSet();
    final declared = (def['requires'] as Map?)?['connectors'];
    if (declared is List) used.addAll(declared.whereType<String>().where(known.contains));
    for (final s in _steps(def)) {
      if (s['type'] != 'tool') continue;
      final tool = s['tool'] as String?;
      final owner = all.where((t) => t.tools.contains(tool));
      used.add(owner.isEmpty ? 'live' : owner.first.id);
    }
    if (RegExp(r'\{\{\s*profile\b').hasMatch(_steps(def).toString())) used.add('details');
    return used;
  }

  /// The phone's calendar is on for the keyboard: turned on, and still
  /// allowed (Connected tools reads it the same way).
  static bool calendarOn(Map<String, dynamic> status) =>
      status['enabled'] == true && (status['permission'] == 'granted' || status['permission'] == 'writeOnly');

  /// Whether each tool can be used now, from what the app already reads for
  /// Connected tools and Profile › Search.
  static Map<String, bool> ready({
    required Map<String, dynamic> google,
    required Map<String, dynamic> calendar,
    required Map<String, dynamic> location,
    required String? bookingLink,
  }) =>
      {
        'meet': google['meet'] == true,
        'booking': (bookingLink ?? '').trim().isNotEmpty,
        'calendar': calendarOn(calendar),
        'location': location['enabled'] == true,
        'details': true,
        'live': true,
      };
}
