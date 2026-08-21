import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/models/view_rule.dart';
import 'package:snapcraft_confdb_builder/services/snapcraft_metadata_builder.dart';

void main() {
  const builder = SnapcraftMetadataBuilder();
  final document = ConfdbSchemaDocument(
    accountId: 'brand-id',
    name: 'weather',
    summary: 'Weather settings',
    storage: StorageNode.map(children: {'v1': StorageNode.map()}),
    views: [
      ConfdbView(
        name: 'consumer',
        rules: [
          ConfdbRule(
            request: ConfdbPath.parse('weather.city'),
            storage: ConfdbPath.parse('v1.city'),
            access: ViewAccess.read,
          ),
        ],
      ),
    ],
  );

  test('builds consumer plug metadata for the selected view', () {
    final yaml = builder.buildConsumerPlug(
      document: document,
      viewName: 'consumer',
    );

    expect(yaml, '''consumer:
  interface: confdb
  account: brand-id
  view: weather/consumer
''');
  });

  test('includes custodian role only when requested', () {
    final yaml = builder.buildConsumerPlug(
      document: document,
      viewName: 'consumer',
      custodian: true,
    );

    expect(yaml, contains('  role: custodian\n'));
  });

  test('rejects a view that does not exist', () {
    expect(
      () => builder.buildConsumerPlug(document: document, viewName: 'missing'),
      throwsArgumentError,
    );
  });
}
