import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/build/glyf_tools.dart';

void main() {
  final meet = {
    'id': 'user.draft',
    'requires': {'fullAccess': true, 'connectors': ['meet'], 'wallet': false},
    'steps': [
      {'id': 's1', 'type': 'tool', 'tool': 'meet.new', 'args': {}, 'out': 'link'},
      {'id': 's2', 'type': 'format', 'template': 'Join me: {{link}}', 'out': 'final'},
    ],
  };

  test('a Meet glyf needs the Meet link fetched on the phone', () {
    expect(GlyfTools.phoneToolsOf(meet), ['meet.new']);
    expect(GlyfTools.usedBy(meet), {'meet'});
  });

  test('server tools and the vault count as their switches, none as phone tools', () {
    final def = {
      'steps': [
        {'id': 's1', 'type': 'tool', 'tool': 'weather.now', 'args': {'place': '{{input}}'}, 'out': 'w'},
        {'id': 's2', 'type': 'tool', 'tool': 'place.here', 'args': {}, 'out': 'here'},
        {'id': 's3', 'type': 'llm', 'prompt': 'Sign it with {{profile}}', 'out': 'final'},
      ],
    };
    expect(GlyfTools.phoneToolsOf(def), isEmpty);
    expect(GlyfTools.usedBy(def), {'live', 'location', 'details'});
  });

  test('ready reads what Connected tools and Search already read', () {
    final ready = GlyfTools.ready(
      google: {'connected': true, 'meet': true},
      calendar: {'enabled': true, 'permission': 'denied'},
      location: {'enabled': false},
      bookingLink: ' ',
    );
    expect(ready['meet'], isTrue);
    expect(ready['calendar'], isFalse);
    expect(ready['location'], isFalse);
    expect(ready['booking'], isFalse);
    expect(ready['live'], isTrue);
  });

  test('every tool id is one the server knows', () {
    expect(GlyfTools.all.map((t) => t.id),
        ['meet', 'booking', 'calendar', 'location', 'details', 'live']);
  });
}
