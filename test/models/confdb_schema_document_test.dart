import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/models/view_rule.dart';

void main() {
  test('creates versioned storage with matching writable rule', () {
    final document = ConfdbSchemaDocument.empty(
      accountId: 'brand-id',
      name: 'weather',
    ).copyWith(
      storage: StorageNode.map(
        children: {
          'v1': StorageNode.map(
            children: {
              'lat': StorageNode.number(minimum: -90, maximum: 90),
            },
          ),
        },
      ),
      views: [
        ConfdbView(
          name: 'admin',
          rules: [
            ConfdbRule(
              request: ConfdbPath.parse('weather.{key}'),
              storage: ConfdbPath.parse('v1.{key}'),
              access: ViewAccess.readWrite,
            ),
          ],
        ),
      ],
    );

    expect(
      document.storage.children['v1']!.children['lat']!.kind,
      StorageKind.number,
    );
    expect(document.views.single.rules.single.placeholders, {'key'});
  });

  test('defensively copies document collections', () {
    final headers = <String, Object?>{'custom-field': 'retained'};
    final document = ConfdbSchemaDocument.empty(
      accountId: 'brand-id',
      name: 'weather',
    ).copyWith(extraHeaders: headers);

    headers['custom-field'] = 'changed';

    expect(document.extraHeaders, {'custom-field': 'retained'});
    expect(
      () => document.extraHeaders['another-field'] = 'value',
      throwsUnsupportedError,
    );
  });
}