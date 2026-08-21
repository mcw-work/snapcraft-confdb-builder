import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/diagnostic.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/models/view_rule.dart';
import 'package:snapcraft_confdb_builder/services/confdb_validator.dart';

void main() {
  const validator = ConfdbValidator();

  test('reports required schema blockers with meaningful locations', () {
    final diagnostics = validator.validate(
      ConfdbSchemaDocument.empty(accountId: '', name: 'Bad_Name'),
    );

    expect(
      diagnostics.map((item) => item.code),
      containsAll([
        'schema.account-id-required',
        'schema.invalid-name',
        'schema.storage-required',
      ]),
    );
    expect(
      diagnostics.every((item) => item.location != null),
      isTrue,
    );
  });

  test('reports an invalid account ID', () {
    final diagnostics = validator.validate(
      documentWith(accountId: 'brand id'),
    );

    expect(
      diagnostics.map((item) => item.code),
      contains('schema.invalid-account-id'),
    );
    expect(
      diagnostics
          .firstWhere((item) => item.code == 'schema.invalid-account-id')
          .location
          ?.path,
      'account-id',
    );
  });

  test('accepts opaque mixed-case Snap Store account IDs', () {
    final diagnostics = validator.validate(
      documentWith(accountId: 'bpyPt7Qr2Qbui3MJMgyzZ3WaQkyj6OkU'),
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(contains('schema.invalid-account-id')),
    );
  });

  test('reports unsupported nodes and constraints as blockers', () {
    final diagnostics = validator.validate(
      documentWith(
        storage: StorageNode.map(
          children: {
            'v1': StorageNode.map(
              children: {
                'alias': StorageNode.alias(alias: 'shared'),
                'anything': StorageNode.any(),
                'pattern': StorageNode.string(pattern: '['),
                'range': StorageNode.integer(minimum: 3, maximum: 2),
              },
            ),
          },
        ),
      ),
    );

    expect(
      diagnostics.map((item) => item.code),
      containsAll([
        'storage.unsupported-alias',
        'storage.unsupported-type',
        'storage.unrepresentable-constraint',
      ]),
    );
    expect(
      diagnostics
          .where((item) => item.isBlocker)
          .every((item) => item.location?.path != null),
      isTrue,
    );
  });

  test('reports malformed source with a source location', () {
    final diagnostics = validator.validateSource('''
type: confdb-schema
account-id: brand-id
name: weather
summary: Weather settings
views:
  admin:
    rules:
      - request: weather.city
        storage: v1.city
        access: write
body: |-
  {"storage": {"v1": {"type": "map", "schema": {}}}}
''');

    expect(diagnostics.single.code, 'source.invalid-yaml');
    expect(diagnostics.single.location?.section, 'source');
  });

  test('reports malformed paths, mismatched placeholders, and duplicates', () {
    final badRule = ConfdbRule(
      request: ConfdbPath.parse('weather..{requestKey}'),
      storage: ConfdbPath.parse('v1.{storageKey}'),
      access: ViewAccess.readWrite,
    );
    final duplicateRule = ConfdbRule(
      request: ConfdbPath.parse('weather..{requestKey}'),
      storage: ConfdbPath.parse('v1.other.{storageKey}'),
      access: ViewAccess.read,
    );
    final diagnostics = validator.validate(
      documentWith(
        views: [
          ConfdbView(name: 'admin', rules: [badRule, duplicateRule]),
          ConfdbView(name: 'reader', rules: [
            ConfdbRule(
              request: ConfdbPath.parse('weather.city'),
              storage: ConfdbPath.parse('v1.city'),
              access: ViewAccess.read,
            ),
            ConfdbRule(
              request: ConfdbPath.parse('weather.country'),
              storage: ConfdbPath.parse('v1.city'),
              access: ViewAccess.read,
            ),
          ]),
        ],
      ),
    );

    expect(
      diagnostics.map((item) => item.code),
      containsAll([
        'rule.malformed-path',
        'rule.placeholder-mismatch',
        'rule.duplicate-request-path',
        'rule.duplicate-storage-mapping',
      ]),
    );
    expect(
      diagnostics
          .where((item) => item.code.startsWith('rule.'))
          .every((item) => item.location?.viewName != null),
      isTrue,
    );
  });

  test('reports naming, version-root, and broad writable advisories', () {
    final diagnostics = validator.validate(
      documentWith(
        name: 'weather_schema',
        storage: StorageNode.map(children: {'settings': StorageNode.map()}),
        views: [
          ConfdbView(
            name: 'Admin_View',
            rules: [
              ConfdbRule(
                request: ConfdbPath.parse('weather'),
                storage: ConfdbPath.parse('v1'),
                access: ViewAccess.readWrite,
              ),
            ],
          ),
        ],
      ),
    );

    expect(
      diagnostics.map((item) => item.code),
      containsAll([
        'schema.naming-violation',
        'view.naming-violation',
        'storage.version-root-missing',
        'rule.overly-broad-writable-mapping',
      ]),
    );
    expect(
      diagnostics
          .where((item) => !item.isBlocker)
          .every((item) => item.severity == DiagnosticSeverity.advisory),
      isTrue,
    );
  });

  test('accepts a representative publishable schema', () {
    final diagnostics = validator.validate(
      documentWith(
        storage: StorageNode.map(
          children: {
            'v1': StorageNode.map(
              children: {'city': StorageNode.string()},
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
      ),
    );

    expect(
      diagnostics.where((item) => item.isBlocker).map((item) => item.code),
      isEmpty,
    );
  });
}

ConfdbSchemaDocument documentWith({
  String accountId = 'brand-id',
  String name = 'weather',
  StorageNode? storage,
  Iterable<ConfdbView> views = const [],
}) => ConfdbSchemaDocument(
  accountId: accountId,
  name: name,
  summary: 'Weather settings',
  storage: storage ?? StorageNode.map(children: {'v1': StorageNode.map()}),
  views: views,
);