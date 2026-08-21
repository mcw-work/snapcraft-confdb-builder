import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/models/view_rule.dart';
import 'package:snapcraft_confdb_builder/services/confdb_source_codec.dart';

void main() {
  const codec = ConfdbSourceCodec();

  test('parses store editor source and preserves supported headers', () {
    const source = '''
type: confdb-schema
account-id: brand-id
name: weather
summary: Weather settings
revision: 7
timestamp: 2026-08-21T10:30:00Z
authority-id: brand-id
views:
  admin:
    rules:
      - request: weather.{key}
        storage: settings.{key}
        access: read-write
body: |-
  {
    "storage": {
      "settings": {
        "type": "map",
        "schema": {
          "city": {"type": "string"}
        }
      }
    }
  }
''';

    final result = codec.parse(source);

    expect(result.applied, isTrue);
    expect(result.diagnostics, isEmpty);
    expect(result.document, isNotNull);
    expect(result.document!.accountId, 'brand-id');
    expect(result.document!.name, 'weather');
    expect(result.document!.summary, 'Weather settings');
    expect(result.document!.revision!.value, '7');
    expect(
      result.document!.revision!.timestamp,
      DateTime.utc(2026, 8, 21, 10, 30),
    );
    expect(result.document!.extraHeaders, {'authority-id': 'brand-id'});
    expect(result.document!.storage.children['settings']!.kind, StorageKind.map);
    expect(
      result.document!.storage.children['settings']!.children['city']!.kind,
      StorageKind.string,
    );
    expect(result.document!.views.single.name, 'admin');
    expect(
      result.document!.views.single.rules.single.access,
      ViewAccess.readWrite,
    );
  });

  test('does not apply malformed YAML', () {
    final result = codec.parse('type: [confdb-schema');

    expect(result.applied, isFalse);
    expect(result.document, isNull);
    expect(result.diagnostics.single.code, 'source.invalid-yaml');
    expect(result.diagnostics.single.isBlocker, isTrue);
  });

  test('does not replace an active document with invalid source', () {
    final activeDocument = ConfdbSchemaDocument.empty(
      accountId: 'brand-id',
      name: 'weather',
    );

    final result = codec.applySource(activeDocument, 'views: [broken');

    expect(result.applied, isFalse);
    expect(result.document, same(activeDocument));
    expect(result.diagnostics.single.code, 'source.invalid-yaml');
  });

  test('does not apply invalid JSON body', () {
    const source = '''
type: confdb-schema
account-id: brand-id
name: weather
summary: Weather settings
body: |-
  {not-json}
''';

    final result = codec.parse(source);

    expect(result.applied, isFalse);
    expect(result.document, isNull);
    expect(result.diagnostics.single.code, 'source.invalid-body-json');
  });

  test('does not apply a body without root storage', () {
    const source = '''
type: confdb-schema
account-id: brand-id
name: weather
summary: Weather settings
body: |-
  {"other": {}}
''';

    final result = codec.parse(source);

    expect(result.applied, isFalse);
    expect(result.document, isNull);
    expect(result.diagnostics.single.code, 'source.missing-storage');
  });

  test('encodes canonical Store editor source', () {
    final source = codec.encode(
      ConfdbSchemaDocument(
        accountId: 'brand-id',
        name: 'weather',
        summary: 'Weather settings',
        revision: SchemaRevision(
          value: '7',
          timestamp: DateTime.utc(2026, 8, 21, 10, 30),
        ),
        extraHeaders: const {
          'authority-id': 'brand-id',
          'brand-id': 'brand-id',
        },
        views: [
          ConfdbView(
            name: 'admin',
            rules: [
              ConfdbRule(
                request: ConfdbPath.parse('weather.{key}'),
                storage: ConfdbPath.parse('settings.{key}'),
                access: ViewAccess.readWrite,
              ),
            ],
          ),
        ],
        storage: StorageNode.map(
          children: {
            'settings': StorageNode.map(
              children: {'city': StorageNode.string()},
            ),
          },
        ),
      ),
    );

    expect(
      source,
      '''type: confdb-schema
account-id: brand-id
name: weather
summary: Weather settings
revision: 7
timestamp: 2026-08-21T10:30:00.000Z
authority-id: brand-id
brand-id: brand-id
views:
  admin:
    rules:
      - request: weather.{key}
        storage: settings.{key}
        access: read-write
body: |-
  {
    "storage": {
      "settings": {
        "type": "map",
        "schema": {
          "city": {
            "type": "string"
          }
        }
      }
    }
  }
''',
    );
  });
}