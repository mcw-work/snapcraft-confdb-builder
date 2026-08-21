import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/view_rule.dart';

void main() {
  test('extracts placeholder names from path segments', () {
    final path = ConfdbPath.parse('weather.location.{field}.{key}');

    expect(path.segments, ['weather', 'location', '{field}', '{key}']);
    expect(path.placeholders, {'field', 'key'});
  });

  test('rule placeholders combine request and storage paths', () {
    final rule = ConfdbRule(
      request: ConfdbPath.parse('weather.{requestKey}'),
      storage: ConfdbPath.parse('v1.{storageKey}'),
      access: ViewAccess.read,
    );

    expect(rule.placeholders, {'requestKey', 'storageKey'});
  });
}